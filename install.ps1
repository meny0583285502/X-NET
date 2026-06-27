# X-NET v7.0 - ULTIMATE (Direct DNS, Tray Icon, UTC Sync)
param([string]$UserEmail = "", [switch]$Silent)

$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"

if (-not (Test-Path $DIR)) { New-Item $DIR -ItemType Directory -Force | Out-Null }

# Resolve email
$EmailFile = "$DIR\user.txt"
if ($UserEmail) { $UserEmail | Out-File $EmailFile -Encoding ASCII -Force }
elseif (Test-Path $EmailFile) { $UserEmail = (Get-Content $EmailFile -First 1).Trim() }
else { if (-not $Silent) { Write-Host "ERROR: No email"; Read-Host }; exit }

$Safe = $UserEmail -replace '@','_at_' -replace '\.','_dot_'

if (-not $Silent) { Write-Host "===== X-NET v7.0 | $UserEmail =====" -ForegroundColor Cyan }

# Fetch profile
try {
    $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop
} catch {
    if (-not $Silent) { Write-Host "    ERROR: Failed to pull profile. Check network." -ForegroundColor Red; Start-Sleep 3 }
    exit
}

# ---------------- UNINSTALL LOGIC ----------------
if ($P.requests.uninstall_approved -eq $true) {
    if (-not $Silent) { Write-Host "[!] Uninstalling X-NET completely..." -ForegroundColor Yellow }
    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
    }
    attrib -r $HOSTS 2>$null
    $h = Get-Content $HOSTS -Raw
    $h = $h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
    [IO.File]::WriteAllText($HOSTS, $h, [Text.Encoding]::UTF8)
    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
    
    # Remove Tasks and Tray
    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
    $StartupShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk"
    Remove-Item $StartupShortcut -Force -ErrorAction SilentlyContinue
    
    "HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox" | ForEach-Object {
        Remove-ItemProperty $_ -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -ErrorAction SilentlyContinue
    }
    ipconfig /flushdns | Out-Null
    
    # Kill running tray process
    Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "tray.ps1" } | Stop-Process -Force -ErrorAction SilentlyContinue
    
    Start-Sleep 1
    Remove-Item $DIR -Recurse -Force -ErrorAction SilentlyContinue
    
    if (-not $Silent) { 
        Write-Host "[+] Removed Successfully. You can close this window." -ForegroundColor Green
        Read-Host "Press Enter to exit" 
    }
    exit
}

# ---------------- PAUSE LOGIC (UTC Synced) ----------------
if ($null -ne $P.requests.pause -and $null -ne $P.requests.pause.until) {
    try {
        $UntilUTC = [datetime]::Parse($P.requests.pause.until).ToUniversalTime()
        if ((Get-Date).ToUniversalTime() -lt $UntilUTC) {
            if (-not $Silent) { Write-Host "[~] PAUSE ACTIVE. Restoring internet temporarily." -ForegroundColor Yellow }
            Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
                Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
            }
            attrib -r $HOSTS 2>$null
            $h = Get-Content $HOSTS -Raw
            $h = $h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
            [IO.File]::WriteAllText($HOSTS, $h, [Text.Encoding]::UTF8)
            ipconfig /flushdns | Out-Null
            if (-not $Silent) { 
                Write-Host "Paused until $([datetime]::Parse($P.requests.pause.until).ToLocalTime().ToString('HH:mm'))" -ForegroundColor Green
                Read-Host "Press Enter to close" 
            }
            exit
        }
    } catch {}
}

# ---------------- BUILD WHITELIST ----------------
$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

[void]$Allowed.Add("googleapis.com")
[void]$Allowed.Add("gstatic.com")
[void]$Allowed.Add("accounts.google.com")
[void]$Allowed.Add("googleusercontent.com")

if ($P.base_sites_enabled -eq $true) {
    try {
        $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop
        $Base.allowed_domains | ForEach-Object {
            $d = $_ -replace "^https?://","" -replace "/$","" -replace "^www\.",""
            [void]$Allowed.Add($d)
        }
    } catch {}
}

if ($P.google_search_enabled -eq $true) {
    [void]$Allowed.Add("google.com")
    [void]$Allowed.Add("google.co.il")
}

if ($P.allowed_domains) {
    $P.allowed_domains | ForEach-Object {
        $d = $_ -replace "^https?://","" -replace "/$","" -replace "^www\.",""
        [void]$Allowed.Add($d)
    }
}

@(
    "meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com",
    "api.emailjs.com","update.microsoft.com","windowsupdate.microsoft.com",
    "download.windowsupdate.com","ctldl.windowsupdate.com","wustat.windows.com",
    "dns.msftncsi.com","login.microsoftonline.com","login.live.com","microsoft.com",
    "office.com","ocsp.digicert.com","ocsp.pki.goog","crl.microsoft.com","pki.goog"
) | ForEach-Object { [void]$Allowed.Add($_) }

# ---------------- RESOLVE IPs (Direct Query, No Adapter changes) ----------------
if (-not $Silent) { Write-Host "[+] Resolving DNS securely..." -ForegroundColor Yellow }
$HostLines = [System.Collections.Generic.List[string]]::new()
$ok = 0

foreach ($root in $Allowed) {
    $variants = @($root)
    if (-not $root.StartsWith("www.")) { $variants += "www.$root" }
    foreach ($v in $variants) {
        try {
            # Bypasses local DNS completely and queries Google directly to avoid glitches
            $res = Resolve-DnsName -Name $v -Server 8.8.8.8 -Type A -ErrorAction SilentlyContinue
            if ($res) {
                foreach ($r in $res) {
                    if ($r.Type -eq 'A') {
                        $HostLines.Add("$($r.IPAddress)`t$v")
                        $ok++
                    }
                }
            }
        } catch {}
    }
}

# ---------------- LOCK DNS ----------------
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    $name = $_.Name
    $idx  = $_.InterfaceIndex
    try {
        Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue
        netsh interface ipv6 set dnsservers name="$name" static ::1 primary 2>&1 | Out-Null
    } catch {}
}
Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled } | ForEach-Object {
    Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue
}

# ---------------- WRITE HOSTS ----------------
attrib -r $HOSTS 2>$null
$block = [System.Collections.Generic.List[string]]::new()
$block.Add("# [XNET] DO NOT EDIT")
$block.Add("# User: $UserEmail | Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$block.Add("127.0.0.1 localhost")
$block.Add("::1 localhost")
$block.Add("")
foreach ($line in $HostLines) { $block.Add($line) }
$block.Add("")
$block.Add("# [/XNET]")

$existing = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue
if (-not $existing) { $existing = "" }
$existing = $existing -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
$final = $existing.TrimEnd() + "`r`n" + ($block -join "`r`n")
[IO.File]::WriteAllText($HOSTS, $final, [Text.Encoding]::UTF8)

# ---------------- SECURE BROWSERS & FIREWALL ----------------
$k = "HKLM:\SOFTWARE\Policies\Google\Chrome"; if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force
Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force
$k = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force
Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force
$k = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"; if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "DNSOverHTTPS" '{"Enabled": false}' -Force

Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "XNET-Telegram" -Direction Outbound -Action Block -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-VPN-UDP" -Direction Outbound -Action Block -Protocol UDP -RemotePort @(1194,51820) -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-Block-QUIC" -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Profile Any -ErrorAction SilentlyContinue | Out-Null
ipconfig /flushdns | Out-Null

# ---------------- DEPLOY TRAY ICON APP ----------------
$TrayCode = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Shield
$notify.Visible = $true
$notify.Text = "X-NET מגן ומסנן (פעיל)"
$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.WindowState = "Minimized"
[System.Windows.Forms.Application]::Run($form)
'@
$TrayCode | Out-File "$DIR\tray.ps1" -Encoding UTF8 -Force

# Create startup shortcut for the tray
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$Shortcut.Save()

# Launch tray now if not running
$TrayRunning = Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "tray.ps1" }
if (-not $TrayRunning) {
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
}

# ---------------- BACKGROUND SYNC TASK (3 MIN) ----------------
$SyncTask = "$DIR\sync.ps1"
"try { Invoke-WebRequest '$GH_RAW/install.ps1' -OutFile '$DIR\install.ps1' -UseBasicParsing; & '$DIR\install.ps1' -UserEmail '$UserEmail' -Silent } catch {}" | Out-File $SyncTask -Encoding UTF8 -Force

schtasks /query /tn "XNET_Sync" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    schtasks /create /tn "XNET_Sync" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SyncTask`"" /sc minute /mo 3 /ru "SYSTEM" /f 2>&1 | Out-Null
}

# ---------------- STATUS UPDATE ----------------
@{
    installed             = $true
    mode                  = "whitelist"
    base_sites_enabled    = $P.base_sites_enabled
    google_search_enabled = $P.google_search_enabled
    last_updated          = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    user                  = $UserEmail
    allowed               = $Allowed.Count
    resolved              = $ok
    version               = "7.0"
} | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force

if (-not $Silent) {
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " X-NET v7.0 - SYNC & TRAY ACTIVE"     -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Start-Process "https://meny0583285502.github.io/X-NET/?user=$UserEmail&installed=1"
    Start-Sleep 1
    Read-Host "Press Enter to exit"
}
