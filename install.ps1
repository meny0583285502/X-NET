# X-NET sync.ps1 - runs every minute as SYSTEM
$DIR    = "C:\XNET"
$HOSTS  = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"

# תיקון: יצירת התיקייה אם היא לא קיימת
if (-not (Test-Path $DIR)) { 
    New-Item -Path $DIR -ItemType Directory -Force | Out-Null 
}

$EmailFile = "$DIR\user.txt"
if (-not (Test-Path $EmailFile)) { exit }
$UserEmail = (Get-Content $EmailFile -First 1).Trim()
$Safe = $UserEmail -replace "@","_at_" -replace "\.","_dot_"

# STEP 2: Fetch profile from GitHub (with Cache-Busting)
try {
    $t = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json?t=$t" -UseBasicParsing -Headers @{"Cache-Control"="no-cache"} -ErrorAction Stop
} catch {
    exit
}

# STEP 3: Uninstall
if ($P.requests.uninstall_approved -eq $true) {
    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
    Get-WmiObject Win32_Process -Filter "name='powershell.exe'" | Where-Object { $_.CommandLine -match "tray\.ps1" } | ForEach-Object { $_.Terminate() }
    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue }
    attrib -r $HOSTS 2>$null
    $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue
    if ($h) { [IO.File]::WriteAllText($HOSTS, ($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""), [Text.Encoding]::UTF8) }
    foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox")) {
        Remove-ItemProperty $k -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -ErrorAction SilentlyContinue
    }
    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
    ipconfig /flushdns | Out-Null
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk" -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    Remove-Item $DIR -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

# STEP 4: Pause
if ($P.requests.pause -and $P.requests.pause.until) {
    try {
        $until = [datetime]::Parse($P.requests.pause.until).ToUniversalTime()
        if ((Get-Date).ToUniversalTime() -lt $until) {
            attrib -r $HOSTS 2>$null
            $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue
            if ($h) { [IO.File]::WriteAllText($HOSTS, ($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""), [Text.Encoding]::UTF8) }
            ipconfig /flushdns | Out-Null
            @{ paused=$true; paused_until=$P.requests.pause.until; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force
            exit
        }
    } catch {}
}

# STEP 5: Build allowed domains list (Only minimal required domains)
$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$systemDomains = @("meny0583285502.github.io","raw.githubusercontent.com","api.emailjs.com")
$systemDomains | ForEach-Object { [void]$Allowed.Add($_) }

if ($P.base_sites_enabled -eq $true) {
    try {
        $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop
        $Base.allowed_domains | ForEach-Object { $d = ($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }
    } catch {}
}
if ($P.google_search_enabled -eq $true) { [void]$Allowed.Add("google.com"); [void]$Allowed.Add("google.co.il") }
if ($P.allowed_domains) {
    $P.allowed_domains | ForEach-Object { $d = ($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }
}

$AllowedList = $Allowed | Sort-Object
$AllowedList | Out-File "$DIR\whitelist.txt" -Encoding UTF8 -Force

# STEP 7: Resolve IPs (Securely, without opening adapter DNS!)
Start-Sleep -Seconds 1
$HostLines = [System.Collections.Generic.List[string]]::new()
$ok = 0
foreach ($root in $AllowedList) {
    $variants = @($root); if (-not $root.StartsWith("www.")) { $variants += "www.$root" }
    foreach ($v in $variants) {
        try {
            $ips = Resolve-DnsName -Name $v -Server 8.8.8.8 -Type A -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPAddress
            foreach ($ip in $ips) { $HostLines.Add("$ip`t$v") }
            $ok++
        } catch {}
    }
}

# STEP 8: Lock DNS to 127.0.0.1
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue } catch {}
}
Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled } | ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue }

# Block DoH in browsers
foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force
    Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force
}
$k = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "DNSOverHTTPS" "{\"Enabled\": false}" -Force

# STEP 9: Write hosts file
attrib -r $HOSTS 2>$null
$block = [System.Collections.Generic.List[string]]::new()
$block.Add("# [XNET] DO NOT EDIT")
$block.Add("# Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Domains: $ok")
$block.Add("127.0.0.1 localhost")
$block.Add("::1 localhost")
$block.Add("")
foreach ($line in $HostLines) { $block.Add($line) }
$block.Add("")
$block.Add("# [/XNET]")
$existing = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue; if (-not $existing) { $existing = "" }
$existing = $existing -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""
[IO.File]::WriteAllText($HOSTS, $existing.TrimEnd() + "`r`n" + ($block -join "`r`n"), [Text.Encoding]::UTF8)

# Firewall rules
if (-not (Get-NetFirewallRule -DisplayName "XNET-Telegram" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "XNET-Telegram"   -Direction Outbound -Action Block -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "XNET-VPN-UDP"    -Direction Outbound -Action Block -Protocol UDP -RemotePort @(1194,51820) -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "XNET-Block-QUIC" -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Profile Any -ErrorAction SilentlyContinue | Out-Null
}

ipconfig /flushdns | Out-Null
@{ installed=$true; paused=$false; base_sites_enabled=$P.base_sites_enabled; google_search_enabled=$P.google_search_enabled; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail; allowed=$ok; version="11.1" } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force
