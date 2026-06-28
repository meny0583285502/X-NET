# X-NET v9.1 - THE FINAL FIX (DNS Restored BEFORE fetch to prevent crash)
param([string]$UserEmail = "", [switch]$Silent)

$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"

if (-not (Test-Path $DIR)) { New-Item $DIR -ItemType Directory -Force | Out-Null }

$EmailFile = "$DIR\user.txt"
if ($UserEmail) { $UserEmail | Out-File $EmailFile -Encoding ASCII -Force }
elseif (Test-Path $EmailFile) { $UserEmail = (Get-Content $EmailFile -First 1).Trim() }
else { if (-not $Silent) { Write-Host "ERROR: No email"; Read-Host }; exit }

$Safe = $UserEmail -replace '@','_at_' -replace '\.','_dot_'
if (-not $Silent) { Write-Host "===== X-NET v9.1 | $UserEmail =====" -ForegroundColor Cyan }

# ==========================================
# 0. CRITICAL FIX: Restore DNS BEFORE fetching so we have internet!
# ==========================================
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue }
ipconfig /flushdns | Out-Null
Start-Sleep 1

# Now we can safely fetch the profile
try { $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop } 
catch { 
    if (-not $Silent) { Write-Host "    ERROR: Failed to pull profile from GitHub. Check network." -ForegroundColor Red; Read-Host }
    exit 
}

# ==========================================
# 1. UNINSTALL LOGIC (Hard Kill everything)
# ==========================================
if ($P.requests.uninstall_approved -eq $true) {
    if (-not $Silent) { Write-Host "[!] Uninstalling X-NET completely..." -ForegroundColor Yellow }
    
    # Kill background tasks
    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
    schtasks /delete /tn "XNET_Blocker" /f 2>$null | Out-Null
    
    # Kill all running powershell scripts related to X-NET
    Get-WmiObject Win32_Process -Filter "name='powershell.exe'" | Where-Object { $_.CommandLine -match "tray.ps1" -or $_.CommandLine -match "sync.ps1" } | ForEach-Object { $_.Terminate() }
    
    # Restore internet and hosts
    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue }
    attrib -r $HOSTS 2>$null
    $h = Get-Content $HOSTS -Raw
    $h = $h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
    [IO.File]::WriteAllText($HOSTS, $h, [Text.Encoding]::UTF8)
    
    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
    "HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox" | ForEach-Object {
        Remove-ItemProperty $_ -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -ErrorAction SilentlyContinue
    }
    ipconfig /flushdns | Out-Null
    
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk" -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    Remove-Item $DIR -Recurse -Force -ErrorAction SilentlyContinue
    
    if (-not $Silent) { 
        Write-Host "[+] Removed Successfully. (Hover over tray icons to clear ghosts)." -ForegroundColor Green
        Read-Host "Press Enter to exit" 
    }
    exit
}

# ==========================================
# 2. PAUSE LOGIC
# ==========================================
if ($null -ne $P.requests.pause -and $null -ne $P.requests.pause.until) {
    try {
        $UntilUTC = [datetime]::Parse($P.requests.pause.until).ToUniversalTime()
        if ((Get-Date).ToUniversalTime() -lt $UntilUTC) {
            Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue }
            attrib -r $HOSTS 2>$null
            $h = Get-Content $HOSTS -Raw
            $h = $h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
            [IO.File]::WriteAllText($HOSTS, $h, [Text.Encoding]::UTF8)
            ipconfig /flushdns | Out-Null
            if (-not $Silent) { Write-Host "[~] PAUSED temporarily." -ForegroundColor Green; Start-Sleep 2 }
            exit
        }
    } catch {}
}

# ==========================================
# 3. BUILD WHITELIST (Strips Names)
# ==========================================
$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$Allowed.Add("googleapis.com"); [void]$Allowed.Add("gstatic.com"); [void]$Allowed.Add("accounts.google.com"); [void]$Allowed.Add("googleusercontent.com")

if ($P.base_sites_enabled -eq $true) {
    try {
        $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop
        $Base.allowed_domains | ForEach-Object { $d = ($_ -split '\|')[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }
    } catch {}
}

if ($P.google_search_enabled -eq $true) { [void]$Allowed.Add("google.com"); [void]$Allowed.Add("google.co.il") }

if ($P.allowed_domains) {
    $P.allowed_domains | ForEach-Object { $d = ($_ -split '\|')[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }
}

@("meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com","api.emailjs.com","update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com","ctldl.windowsupdate.com","wustat.windows.com","dns.msftncsi.com","login.microsoftonline.com","login.live.com","microsoft.com","office.com","ocsp.digicert.com","ocsp.pki.goog","crl.microsoft.com","pki.goog") | ForEach-Object { [void]$Allowed.Add($_) }

# ==========================================
# 4. SECURE RESOLVE (Using ISP DNS)
# ==========================================
if (-not $Silent) { Write-Host "[+] Resolving addresses securely..." -ForegroundColor Yellow }

# Sleep a bit more to ensure the DHCP adapter has an IP from the router
Start-Sleep -Seconds 3

$HostLines = [System.Collections.Generic.List[string]]::new(); $ok = 0
foreach ($root in $Allowed) {
    $variants = @($root); if (-not $root.StartsWith("www.")) { $variants += "www.$root" }
    foreach ($v in $variants) {
        try {
            $ips = [Net.Dns]::GetHostAddresses($v) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
            foreach ($ip in $ips) { $HostLines.Add("$($ip.IPAddressToString)`t$v") }
            $ok++
        } catch {}
    }
}

# ==========================================
# 5. LOCK DNS & FIREWALL
# ==========================================
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    $name = $_.Name; $idx = $_.InterfaceIndex
    try { Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue; netsh interface ipv6 set dnsservers name="$name" static ::1 primary 2>&1 | Out-Null } catch {}
}
Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled } | ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue }

attrib -r $HOSTS 2>$null
$block = [System.Collections.Generic.List[string]]::new()
$block.Add("# [XNET] DO NOT EDIT"); $block.Add("# User: $UserEmail | Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"); $block.Add("127.0.0.1 localhost"); $block.Add("::1 localhost"); $block.Add("")
foreach ($line in $HostLines) { $block.Add($line) }
$block.Add(""); $block.Add("# [/XNET]")

$existing = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue; if (-not $existing) { $existing = "" }
$existing = $existing -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
[IO.File]::WriteAllText($HOSTS, $existing.TrimEnd() + "`r`n" + ($block -join "`r`n"), [Text.Encoding]::UTF8)

$k = "HKLM:\SOFTWARE\Policies\Google\Chrome"; if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }; Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force; Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force
$k = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }; Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force; Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force
$k = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"; if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }; Set-ItemProperty $k "DNSOverHTTPS" '{"Enabled": false}' -Force

Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "XNET-Telegram" -Direction Outbound -Action Block -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-VPN-UDP" -Direction Outbound -Action Block -Protocol UDP -RemotePort @(1194,51820) -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-Block-QUIC" -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Profile Any -ErrorAction SilentlyContinue | Out-Null
ipconfig /flushdns | Out-Null

# ==========================================
# 6. TRAY ICON (WITH MUTEX TO PREVENT DUPLICATES)
# ==========================================
$TrayCode = @'
$mutex = New-Object System.Threading.Mutex($false, "Global\XNET_TRAY_MUTEX")
if (-not $mutex.WaitOne(0, $false)) { exit }

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

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$Shortcut.Save()

Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`"" -ErrorAction SilentlyContinue

# ==========================================
# 7. SYNC TASK
# ==========================================
$SyncTask = "$DIR\sync.ps1"
"try { Invoke-WebRequest '$GH_RAW/install.ps1' -OutFile '$DIR\install.ps1' -UseBasicParsing; & '$DIR\install.ps1' -UserEmail '$UserEmail' -Silent } catch {}" | Out-File $SyncTask -Encoding UTF8 -Force

schtasks /query /tn "XNET_Sync" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    schtasks /create /tn "XNET_Sync" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SyncTask`"" /sc minute /mo 3 /ru "SYSTEM" /f 2>&1 | Out-Null
}

@{ installed = $true; mode = "whitelist"; base_sites_enabled = $P.base_sites_enabled; google_search_enabled = $P.google_search_enabled; last_updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user = $UserEmail; allowed = $Allowed.Count; version = "9.1" } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force

if (-not $Silent) {
    Start-Process "https://meny0583285502.github.io/X-NET/?user=$UserEmail&installed=1"
    Start-Sleep 1; exit
}
