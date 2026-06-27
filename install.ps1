# X-NET v5 - TRUE WHITELIST
# DNS -> 127.0.0.1 (blocks everything)
# Hosts file -> only allowed domains with real IPs
param([string]$UserEmail = "")

$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"



if (-not (Test-Path $DIR)) { New-Item $DIR -ItemType Directory -Force | Out-Null }

# Resolve email
$EmailFile = "$DIR\user.txt"
if ($UserEmail) { $UserEmail | Out-File $EmailFile -Encoding ASCII -Force }
elseif (Test-Path $EmailFile) { $UserEmail = (Get-Content $EmailFile -First 1).Trim() }
else { Write-Host "ERROR: No email"; Read-Host; exit }

$Safe = $UserEmail -replace '@','_at_' -replace '\.','_dot_'

Write-Host "===== X-NET v5 | $UserEmail =====" -ForegroundColor Cyan

# Fetch profile
Write-Host "[1] Fetching profile from GitHub..." -ForegroundColor Yellow
try {
    $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop
    Write-Host "    OK" -ForegroundColor Green
} catch {
    Write-Host "    ERROR: $_" -ForegroundColor Red; Read-Host; exit
}

# UNINSTALL
if ($P.requests.uninstall_approved -eq $true) {
    Write-Host "[!] Uninstall approved..." -ForegroundColor Yellow
    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
    }
    attrib -r $HOSTS 2>$null
    $h = Get-Content $HOSTS -Raw
    $h = $h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
    [IO.File]::WriteAllText($HOSTS, $h, [Text.Encoding]::UTF8)
    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
    schtasks /delete /tn "XNET_Blocker" /f 2>$null | Out-Null
    "HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox" | ForEach-Object {
        Remove-ItemProperty $_ -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -ErrorAction SilentlyContinue
    }
    ipconfig /flushdns | Out-Null
    Write-Host "[+] Removed. Restart browser." -ForegroundColor Green
    Start-Sleep 1
    Remove-Item $DIR -Recurse -Force -ErrorAction SilentlyContinue
    Read-Host; exit
}

# PAUSE
if ($P.requests.pause_until) {
    try {
        $Until = [datetime]::Parse($P.requests.pause_until)
        if ((Get-Date) -lt $Until) {
            $mins = [int]($Until - (Get-Date)).TotalMinutes
            Write-Host "[~] PAUSED for $mins more minutes" -ForegroundColor Yellow
            Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
                Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
            }
            attrib -r $HOSTS 2>$null
            $h = Get-Content $HOSTS -Raw
            $h = $h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
            [IO.File]::WriteAllText($HOSTS, $h, [Text.Encoding]::UTF8)
            ipconfig /flushdns | Out-Null
            schtasks /create /tn "XNET_Resume" /tr "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\updater.ps1`"" /sc once /st $Until.ToString("HH:mm") /f 2>$null | Out-Null
            Write-Host "    Will resume at $($Until.ToString('HH:mm'))" -ForegroundColor Green
            Read-Host; exit
        }
    } catch {}
}

# BUILD WHITELIST
Write-Host "[2] Building whitelist..." -ForegroundColor Yellow
$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

# Base whitelist from GitHub
try {
    $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop
    $Base.allowed_domains | ForEach-Object {
        $d = $_ -replace "^https?://","" -replace "/$","" -replace "^www\.",""
        [void]$Allowed.Add($d)
    }
    Write-Host "    Base whitelist: $($Base.allowed_domains.Count) domains" -ForegroundColor Green
} catch { Write-Host "    Base whitelist not found - continuing" -ForegroundColor Gray }

# Profile whitelist
if ($P.allowed_domains) {
    $P.allowed_domains | ForEach-Object {
        $d = $_ -replace "^https?://","" -replace "/$","" -replace "^www\.",""
        [void]$Allowed.Add($d)
    }
    Write-Host "    Profile domains: $($P.allowed_domains.Count)" -ForegroundColor Green
}

# Block Google search if admin set flag
$blockGoogle = ($P.block_google_search -eq $true)
if (-not $blockGoogle) {
    [void]$Allowed.Add("google.com")
    [void]$Allowed.Add("googleapis.com")
    [void]$Allowed.Add("gstatic.com")
    [void]$Allowed.Add("accounts.google.com")
}

# Always allow - needed for X-NET itself to work
@(
    "meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com",
    "api.emailjs.com","fonts.googleapis.com","fonts.gstatic.com","gstatic.com",
    "update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com",
    "ctldl.windowsupdate.com","wustat.windows.com","dns.msftncsi.com",
    "login.microsoftonline.com","login.live.com","microsoft.com","office.com",
    "ocsp.digicert.com","ocsp.pki.goog","crl.microsoft.com","pki.goog",
    "msftconnecttest.com","msftncsi.com"
) | ForEach-Object { [void]$Allowed.Add($_) }

Write-Host "    Total unique roots: $($Allowed.Count)" -ForegroundColor Cyan

# RESOLVE IPs FOR WHITELIST
Write-Host "[3] Resolving IPs (using current DNS before locking)..." -ForegroundColor Yellow

# First restore DNS temporarily to resolve
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
}
Start-Sleep 1
ipconfig /flushdns | Out-Null

$HostLines = [System.Collections.Generic.List[string]]::new()
$ok = 0; $fail = 0

foreach ($root in $Allowed) {
    $variants = @($root)
    if (-not $root.StartsWith("www.")) { $variants += "www.$root" }

    foreach ($v in $variants) {
        try {
            $ips = [Net.Dns]::GetHostAddresses($v) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
            if ($ips) {
                $HostLines.Add("$($ips.IPAddressToString)`t$v")
                $ok++
            }
        } catch { $fail++ }
    }
}

Write-Host "    Resolved: $ok IPs | Failed: $fail" -ForegroundColor Green

# LOCK DNS TO 127.0.0.1 (blocks all non-hosts traffic)
Write-Host "[4] Locking DNS - IPv4 + IPv6..." -ForegroundColor Yellow
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    $name = $_.Name
    $idx  = $_.InterfaceIndex
    try {
        Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue
        netsh interface ipv6 set dnsservers name="$name" static ::1 primary 2>&1 | Out-Null
        Write-Host "    $name -> 127.0.0.1 / ::1" -ForegroundColor Green
    } catch { Write-Host "    $name -> $_" -ForegroundColor Red }
}
# Disable IPv6 binding so router cant answer DNS via IPv6
Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled } | ForEach-Object {
    Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue
}
Write-Host "    IPv6 disabled on all adapters" -ForegroundColor Green

# WRITE HOSTS FILE
Write-Host "[5] Writing hosts file..." -ForegroundColor Yellow
attrib -r $HOSTS 2>$null

$block = [System.Collections.Generic.List[string]]::new()
$block.Add("# [XNET] DO NOT EDIT")
$block.Add("# User: $UserEmail | Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$block.Add("# Allowed: $($Allowed.Count) roots | Resolved: $ok IPs")
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

$wrote = $false; $try = 0
while (-not $wrote -and $try -lt 5) {
    try { [IO.File]::WriteAllText($HOSTS, $final, [Text.Encoding]::UTF8); $wrote = $true }
    catch { $try++; Start-Sleep 2 }
}

Write-Host "    Written: $ok entries" -ForegroundColor Green

# DISABLE DoH IN BROWSERS (prevent bypass)
Write-Host "[6] Disabling DoH in browsers..." -ForegroundColor Yellow
# Chrome
$k = "HKLM:\SOFTWARE\Policies\Google\Chrome"
if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force
Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force

# Edge  
$k = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force
Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force

# Firefox
$k = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "DNSOverHTTPS" '{"Enabled": false}' -Force

# Firefox user.js fallback
$ffProfiles = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -ErrorAction SilentlyContinue
foreach ($ffp in $ffProfiles) {
    "user_pref(`"network.trr.mode`", 5);" | Out-File "$($ffp.FullName)\user.js" -Encoding UTF8 -Force
}
Write-Host "    Done" -ForegroundColor Green

# FIREWALL - Block Telegram by IP + VPN ports
Write-Host "[7] Firewall rules..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "XNET-Telegram" -Direction Outbound -Action Block `
    -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") `
    -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-VPN-UDP1194" -Direction Outbound -Action Block `
    -Protocol UDP -RemotePort 1194 -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-VPN-UDP51820" -Direction Outbound -Action Block `
    -Protocol UDP -RemotePort 51820 -Profile Any -ErrorAction SilentlyContinue | Out-Null
Write-Host "    Done" -ForegroundColor Green

ipconfig /flushdns | Out-Null

# STARTUP TASK
Write-Host "[8] Startup task..." -ForegroundColor Yellow
$updater = "$DIR\updater.ps1"
"try { Invoke-WebRequest '$GH_RAW/install.ps1' -OutFile '$DIR\run.ps1' -UseBasicParsing; & '$DIR\run.ps1' } catch { & '$DIR\run.ps1' -ErrorAction SilentlyContinue }" | Out-File $updater -Encoding UTF8 -Force

schtasks /query /tn "XNET_Blocker" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    schtasks /create /tn "XNET_Blocker" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$updater`"" /sc onlogon /rl highest /f 2>$null | Out-Null
    Write-Host "    Task created" -ForegroundColor Green
} else {
    Write-Host "    Task already exists" -ForegroundColor Green
}

# STATUS FILE
@{
    installed    = $true
    mode         = "whitelist"
    block_google = $blockGoogle
    last_updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    user         = $UserEmail
    allowed      = $Allowed.Count
    resolved     = $ok
    version      = "5.0"
} | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host " X-NET v5 - EVERYTHING BLOCKED"       -ForegroundColor Green
Write-Host " Allowed: $($Allowed.Count) domains"  -ForegroundColor Green
Write-Host " Resolved IPs in hosts: $ok"          -ForegroundColor Green
Write-Host " DNS locked: 127.0.0.1"               -ForegroundColor Green
Write-Host " Block Google search: $blockGoogle"   -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host " RESTART YOUR BROWSER NOW"            -ForegroundColor Yellow
Write-Host ""
Start-Process "https://meny0583285502.github.io/X-NET/?user=$UserEmail&installed=1&allowed=$($Allowed.Count)&resolved=$ok"
Read-Host "Press Enter to close"
