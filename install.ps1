# X-NET v6.0 - TRUE WHITELIST + AUTO SYNC
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

if (-not $Silent) { Write-Host "===== X-NET v6.0 | $UserEmail =====" -ForegroundColor Cyan }

# Fetch profile
try {
    $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop
} catch {
    if (-not $Silent) { Write-Host "    ERROR: $_" -ForegroundColor Red; Read-Host }
    exit
}

# UNINSTALL LOGIC
if ($P.requests.uninstall_approved -eq $true) {
    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
    }
    attrib -r $HOSTS 2>$null
    $h = Get-Content $HOSTS -Raw
    $h = $h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
    [IO.File]::WriteAllText($HOSTS, $h, [Text.Encoding]::UTF8)
    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
    schtasks /delete /tn "XNET_Blocker" /f 2>$null | Out-Null
    
    "HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox" | ForEach-Object {
        Remove-ItemProperty $_ -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -ErrorAction SilentlyContinue
    }
    ipconfig /flushdns | Out-Null
    Start-Sleep 1
    Remove-Item $DIR -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $Silent) { Write-Host "[+] Removed Successfully. Restart browser." -ForegroundColor Green; Read-Host }
    exit
}

# PAUSE LOGIC
if ($null -ne $P.requests.pause -and $null -ne $P.requests.pause.until) {
    try {
        $Until = [datetime]($P.requests.pause.until)
        if ((Get-Date) -lt $Until) {
            Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
                Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
            }
            attrib -r $HOSTS 2>$null
            $h = Get-Content $HOSTS -Raw
            $h = $h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
            [IO.File]::WriteAllText($HOSTS, $h, [Text.Encoding]::UTF8)
            ipconfig /flushdns | Out-Null
            if (-not $Silent) { Write-Host "[~] PAUSED until $($Until.ToString('HH:mm'))" -ForegroundColor Yellow; Read-Host }
            exit
        }
    } catch {}
}

# BUILD WHITELIST
$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

# Core Dependencies for Gemini and loading Google services correctly
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

# RESOLVE IPs (Force Google DNS temporarily for fast and reliable resolution)
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses "8.8.8.8","1.1.1.1" -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
ipconfig /flushdns | Out-Null

$HostLines = [System.Collections.Generic.List[string]]::new()
$ok = 0

foreach ($root in $Allowed) {
    $variants = @($root)
    if (-not $root.StartsWith("www.")) { $variants += "www.$root" }
    foreach ($v in $variants) {
        try {
            $ips = [Net.Dns]::GetHostAddresses($v) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
            if ($ips) {
                foreach ($ip in $ips) { $HostLines.Add("$($ip.IPAddressToString)`t$v") }
                $ok++
            }
        } catch {}
    }
}

# LOCK DNS TO 127.0.0.1
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

# WRITE HOSTS FILE
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

# DISABLE DoH IN BROWSERS
$k = "HKLM:\SOFTWARE\Policies\Google\Chrome"; if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force
Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force
$k = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force
Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force
$k = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"; if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "DNSOverHTTPS" '{"Enabled": false}' -Force

# FIREWALL RULES
Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "XNET-Telegram" -Direction Outbound -Action Block -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-VPN-UDP" -Direction Outbound -Action Block -Protocol UDP -RemotePort @(1194,51820) -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-Block-QUIC" -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Profile Any -ErrorAction SilentlyContinue | Out-Null
ipconfig /flushdns | Out-Null

# BACKGROUND SYNC TASK (RUNS EVERY 3 MINUTES)
$SyncTask = "$DIR\sync.ps1"
"try { Invoke-WebRequest '$GH_RAW/install.ps1' -OutFile '$DIR\install.ps1' -UseBasicParsing; & '$DIR\install.ps1' -UserEmail '$UserEmail' -Silent } catch {}" | Out-File $SyncTask -Encoding UTF8 -Force

schtasks /create /tn "XNET_Sync" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SyncTask`"" /sc minute /mo 3 /ru "SYSTEM" /f 2>&1 | Out-Null

# STATUS FILE
@{
    installed             = $true
    mode                  = "whitelist"
    base_sites_enabled    = $P.base_sites_enabled
    google_search_enabled = $P.google_search_enabled
    last_updated          = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    user                  = $UserEmail
    allowed               = $Allowed.Count
    resolved              = $ok
    version               = "6.0"
} | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force

if (-not $Silent) {
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " X-NET v6.0 - SYNC ACTIVE"            -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Start-Process "https://meny0583285502.github.io/X-NET/?user=$UserEmail&installed=1"
    Start-Sleep 2
}
