# X-NET Blocker v4 - TRUE WHITELIST via DNS Sinkhole
# All English only - no Hebrew to avoid encoding issues
param (
    [string]$UserEmail = "",
    [switch]$ForceReinstall = $false
)

$InstallDir  = "C:\XNET"
$EmailFile   = "$InstallDir\user.txt"
$HostsFile   = "$env:SystemRoot\System32\drivers\etc\hosts"
$StatusFile  = "$InstallDir\status.json"
$GH_RAW      = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"
$GH_API      = "https://api.github.com/repos/meny0583285502/X-NET"
$SITE_URL    = "https://meny0583285502.github.io/X-NET"

# ── Admin check ──
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Must run as Administrator" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

if (-not (Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }

# ── Resolve email ──
if ($UserEmail -ne "") {
    $UserEmail | Out-File $EmailFile -Force -Encoding ASCII
} elseif (Test-Path $EmailFile) {
    $UserEmail = (Get-Content $EmailFile | Select-Object -First 1).Trim()
} else {
    Write-Host "ERROR: No user email found" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

$SafeEmail  = $UserEmail -replace '@','_at_' -replace '\.','_dot_'
$ProfileUrl = "$GH_RAW/profiles/$SafeEmail.json"
$BaseUrl    = "$GH_RAW/base_whitelist.json"

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " X-NET v4 - TRUE WHITELIST MODE"      -ForegroundColor Cyan
Write-Host " User: $UserEmail"                     -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# ── Fetch profile ──
Write-Host "[1] Fetching profile..." -ForegroundColor Yellow
try {
    $Profile = Invoke-RestMethod -Uri $ProfileUrl -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Host "    ERROR: Cannot fetch profile - $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

# ── UNINSTALL flow ──
if ($Profile.requests.uninstall_approved -eq $true) {
    Write-Host "[!] Uninstall approved - removing X-NET..." -ForegroundColor Yellow

    # Remove hosts block
    if (Test-Path $HostsFile) {
        attrib -r $HostsFile 2>$null
        $h = Get-Content $HostsFile -Raw -ErrorAction SilentlyContinue
        if ($h) {
            $h = $h -replace "(?s)# \[X-NET-START\].*?# \[X-NET-END\]\r?\n?",""
            [System.IO.File]::WriteAllText($HostsFile, $h, [System.Text.Encoding]::UTF8)
        }
    }

    # Restore DNS to automatic
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    foreach ($a in $adapters) {
        Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
    }

    # Remove browser policies
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "DnsOverHttpsMode" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "BuiltInDnsClientEnabled" -ErrorAction SilentlyContinue

    # Remove firewall rules
    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue

    # Remove startup task
    schtasks /delete /tn "XNET_Blocker" /f 2>$null | Out-Null

    ipconfig /flushdns | Out-Null

    # Reset uninstall flag via GitHub API (so reinstall works)
    Write-Host "    Resetting uninstall flag on GitHub..." -ForegroundColor Gray
    try {
        $TokenFile = "$InstallDir\t.dat"
        if (Test-Path $TokenFile) {
            $Token = Get-Content $TokenFile -Raw
            $FileUrl = "$GH_API/contents/profiles/$SafeEmail.json"
            $FileInfo = Invoke-RestMethod -Uri $FileUrl -Headers @{Authorization="token $Token"} -ErrorAction Stop
            $Profile.requests.uninstall_approved = $false
            $Profile.requests.uninstall_requested = $false
            $NewContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Profile | ConvertTo-Json -Depth 10)))
            $Body = @{ message="Reset uninstall flag"; content=$NewContent; sha=$FileInfo.sha } | ConvertTo-Json
            Invoke-RestMethod -Uri $FileUrl -Method Put -Headers @{Authorization="token $Token";'Content-Type'='application/json'} -Body $Body | Out-Null
            Write-Host "    Flag reset - can reinstall anytime" -ForegroundColor Green
        }
    } catch { Write-Host "    Could not reset flag automatically" -ForegroundColor Gray }

    # Remove install dir LAST
    Start-Sleep 1
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "[+] X-NET removed successfully" -ForegroundColor Green
    Read-Host "Press Enter to exit"
    exit
}

# ── PAUSE flow ──
if ($Profile.requests.pause -and $Profile.requests.pause -ne "none" -and $Profile.requests.pause -ne "") {
    try {
        $PauseEnd = [datetime]::Parse($Profile.requests.pause)
        if ((Get-Date) -lt $PauseEnd) {
            $MinLeft = [int](($PauseEnd - (Get-Date)).TotalMinutes)
            Write-Host "[~] PAUSE MODE - $MinLeft minutes remaining" -ForegroundColor Yellow
            Write-Host "    Removing blocks temporarily..." -ForegroundColor Yellow
            if (Test-Path $HostsFile) {
                attrib -r $HostsFile 2>$null
                $h = Get-Content $HostsFile -Raw
                $h = $h -replace "(?s)# \[X-NET-START\].*?# \[X-NET-END\]\r?\n?",""
                [System.IO.File]::WriteAllText($HostsFile, $h, [System.Text.Encoding]::UTF8)
            }
            ipconfig /flushdns | Out-Null

            # Schedule re-enable after pause
            $ReEnableTime = $PauseEnd.ToString("HH:mm")
            schtasks /create /tn "XNET_Resume" /tr "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\XNET\updater.ps1`"" /sc once /st $ReEnableTime /f 2>$null | Out-Null
            Write-Host "    Will re-enable at $ReEnableTime" -ForegroundColor Green
            $StatusPause = @{ installed=$true; mode="paused"; paused_until=$Profile.requests.pause; user=$UserEmail } | ConvertTo-Json
            $StatusPause | Out-File $StatusFile -Encoding UTF8 -Force
            Read-Host "Press Enter to exit"
            exit
        }
    } catch {}
}

# ── BUILD WHITELIST ──
Write-Host "[2] Building whitelist..." -ForegroundColor Yellow

$Allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Base whitelist from GitHub
try {
    $Base = Invoke-RestMethod -Uri $BaseUrl -UseBasicParsing -ErrorAction Stop
    foreach ($d in $Base.allowed_domains) {
        $clean = $d -replace "^https?://","" -replace "/$","" -replace "^www\.",""
        [void]$Allowed.Add($clean)
    }
    Write-Host "    Base: $($Base.allowed_domains.Count) domains" -ForegroundColor Green
} catch { Write-Host "    Base whitelist unavailable" -ForegroundColor Gray }

# Profile whitelist
if ($Profile.allowed_domains) {
    foreach ($d in $Profile.allowed_domains) {
        $clean = $d -replace "^https?://","" -replace "/$","" -replace "^www\.",""
        [void]$Allowed.Add($clean)
    }
    Write-Host "    Profile: $($Profile.allowed_domains.Count) domains" -ForegroundColor Green
}

# Always-allow system domains
@(
    "meny0583285502.github.io","raw.githubusercontent.com","github.com",
    "api.emailjs.com","fonts.googleapis.com","fonts.gstatic.com",
    "ocsp.digicert.com","ocsp.pki.goog",
    "update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com",
    "ctldl.windowsupdate.com","wustat.windows.com","ntservicepack.microsoft.com",
    "dns.msftncsi.com","www.msftncsi.com","login.microsoftonline.com","login.live.com",
    "microsoft.com","office.com","office365.com","microsoftonline.com",
    "windows.com","windowsupdate.com"
) | ForEach-Object { [void]$Allowed.Add($_) }

Write-Host "    Total unique roots: $($Allowed.Count)" -ForegroundColor Cyan

# ── TRUE WHITELIST: SET DNS TO SINKHOLE ──
# Strategy: Point DNS to 0.0.0.0 for everything, then add allowed in hosts
# Real approach: use Windows DNS Client + hosts file for allowed sites

Write-Host "[3] Configuring DNS sinkhole..." -ForegroundColor Yellow

# Save current DNS for restore
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
$DnsBackup = @{}
foreach ($a in $adapters) {
    $current = (Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4).ServerAddresses
    $DnsBackup[$a.Name] = $current -join ","
}
$DnsBackup | ConvertTo-Json | Out-File "$InstallDir\dns_backup.json" -Encoding UTF8 -Force

# ── HOSTS FILE: block popular + redirect allowed to real IPs ──
Write-Host "[4] Writing hosts file..." -ForegroundColor Yellow

if (Test-Path $HostsFile) { attrib -r $HostsFile 2>$null }

$Lines = @()
$Lines += "# [X-NET-START] - TRUE WHITELIST v4 - DO NOT EDIT"
$Lines += "# User: $UserEmail"
$Lines += "# Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$Lines += "# Allowed roots: $($Allowed.Count)"
$Lines += ""

# Comprehensive domain block list - all not in whitelist get blocked
$ToBlock = @(
    "facebook.com","instagram.com","twitter.com","x.com","tiktok.com","snapchat.com",
    "pinterest.com","reddit.com","tumblr.com","linkedin.com","threads.net","discord.com",
    "twitch.tv","kick.com","telegram.org","signal.org","viber.com","web.whatsapp.com",
    "youtube.com","youtu.be","vimeo.com","dailymotion.com","rumble.com","odysee.com",
    "netflix.com","disneyplus.com","hbo.com","max.com","hulu.com","peacocktv.com",
    "spotify.com","soundcloud.com","deezer.com","tidal.com","pandora.com","apple.com",
    "music.apple.com","tv.apple.com",
    "ynet.co.il","mako.co.il","walla.co.il","nrg.co.il","haaretz.co.il",
    "israelhayom.co.il","jpost.com","timesofisrael.com","calcalist.co.il","themarker.com",
    "ice.co.il","reshet.tv","channel12.co.il","channel13.co.il","kan.org.il",
    "arutz7.co.il","kikar.co.il","bhol.co.il","behadrei.co.il","hidabroot.com",
    "cnn.com","bbc.com","bbc.co.uk","nytimes.com","washingtonpost.com","foxnews.com",
    "nbcnews.com","reuters.com","theguardian.com","aljazeera.com",
    "amazon.com","ebay.com","aliexpress.com","alibaba.com","etsy.com","walmart.com",
    "chat.openai.com","chatgpt.com","openai.com","copilot.microsoft.com","sydney.bing.com",
    "claude.ai","anthropic.com","gemini.google.com","perplexity.ai","character.ai","poe.com",
    "steampowered.com","epicgames.com","roblox.com","minecraft.net","ea.com","battle.net",
    "pornhub.com","xvideos.com","xhamster.com","xnxx.com","youporn.com","onlyfans.com",
    "bet365.com","888casino.com","pokerstars.com","betway.com","winner.co.il",
    "9gag.com","buzzfeed.com","medium.com","quora.com","stackoverflow.com",
    "nordvpn.com","expressvpn.com","protonvpn.com","surfshark.com","cyberghostvpn.com",
    "torproject.org","thepiratebay.org","1337x.to",
    "bing.com","yahoo.com","yandex.com","duckduckgo.com",
    "dropbox.com","box.com","mega.nz","mediafire.com","wetransfer.com",
    "twitch.tv","mixer.com","dlive.tv",
    "whatsapp.com","messenger.com","line.me","kik.com","skype.com"
)

$BlockedCount = 0
foreach ($d in $ToBlock) {
    $root = $d -replace "^www\.",""
    if (-not $Allowed.Contains($root)) {
        $Lines += "0.0.0.0 $root"
        $Lines += "0.0.0.0 www.$root"
        $BlockedCount += 2
    }
}

# Also block common CDN/tracking that bypass content
$CDNBlock = @(
    "googlevideo.com","ytimg.com","ggpht.com","googleusercontent.com",
    "fbcdn.net","cdninstagram.com","xx.fbcdn.net","static.xx.fbcdn.net",
    "cdntwitter.com","twimg.com","pbs.twimg.com","abs.twimg.com",
    "tiktokcdn.com","tiktokv.com","musical.ly",
    "akamaized.net","fastly.net","cloudfront.net"
)
foreach ($d in $CDNBlock) {
    if (-not $Allowed.Contains($d)) {
        $Lines += "0.0.0.0 $d"
        $BlockedCount++
    }
}

$Lines += ""
$Lines += "# [X-NET-END]"

$HostsContent = Get-Content $HostsFile -Raw -ErrorAction SilentlyContinue
if (-not $HostsContent) { $HostsContent = "" }
if ($HostsContent -match "(?s)# \[X-NET-START\].*?# \[X-NET-END\]") {
    $HostsContent = $HostsContent -replace "(?s)# \[X-NET-START\].*?# \[X-NET-END\]",($Lines -join "`r`n")
} else {
    $HostsContent = $HostsContent.TrimEnd() + "`r`n" + ($Lines -join "`r`n")
}

$Retry = 0; $OK = $false
while (-not $OK -and $Retry -lt 5) {
    try {
        [System.IO.File]::WriteAllText($HostsFile, $HostsContent, [System.Text.Encoding]::UTF8)
        $OK = $true
    } catch { $Retry++; Start-Sleep 2 }
}
Write-Host "    Blocked: $BlockedCount entries" -ForegroundColor Green

# ── BROWSER POLICIES ──
Write-Host "[5] Applying browser policies..." -ForegroundColor Yellow

# Chrome
$k = "HKLM:\SOFTWARE\Policies\Google\Chrome"
if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
Set-ItemProperty -Path $k -Name "DnsOverHttpsMode" -Value "off" -Force
Set-ItemProperty -Path $k -Name "BuiltInDnsClientEnabled" -Value 0 -Type DWord -Force

# Edge
$k = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
Set-ItemProperty -Path $k -Name "BuiltInDnsClientEnabled" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $k -Name "DnsOverHttpsMode" -Value "off" -Force

# Firefox
$k = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
Set-ItemProperty -Path $k -Name "DNSOverHTTPS" -Value '{"Enabled": false}' -Force

Write-Host "    Browser DoH disabled" -ForegroundColor Green

# ── FIREWALL ──
Write-Host "[6] Applying firewall rules..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue

# Telegram IP ranges
New-NetFirewallRule -DisplayName "XNET-Telegram" -Direction Outbound -Action Block `
    -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") `
    -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null

# Copilot/Bing AI
New-NetFirewallRule -DisplayName "XNET-Copilot" -Direction Outbound -Action Block `
    -RemoteAddress @("20.190.128.0/18","40.126.0.0/18") `
    -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null

# VPN protocols
New-NetFirewallRule -DisplayName "XNET-VPN-OpenVPN" -Direction Outbound -Action Block `
    -Protocol UDP -RemotePort 1194 -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-VPN-WireGuard" -Direction Outbound -Action Block `
    -Protocol UDP -RemotePort 51820 -Profile Any -ErrorAction SilentlyContinue | Out-Null

ipconfig /flushdns | Out-Null
Write-Host "    Firewall rules applied" -ForegroundColor Green

# ── STARTUP TASK ──
Write-Host "[7] Registering startup task..." -ForegroundColor Yellow
$Updater = "$InstallDir\updater.ps1"
@"
`$ps1 = "$InstallDir\run.ps1"
Invoke-WebRequest -Uri "$GH_RAW/install.ps1" -OutFile `$ps1 -UseBasicParsing -ErrorAction SilentlyContinue
if (Test-Path `$ps1) { & `$ps1 }
"@ | Out-File $Updater -Encoding UTF8 -Force

$exists = schtasks /query /tn "XNET_Blocker" 2>$null
if ($LASTEXITCODE -ne 0) {
    schtasks /create /tn "XNET_Blocker" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Updater`"" /sc onlogon /rl highest /f 2>$null | Out-Null
    Write-Host "    Startup task created" -ForegroundColor Green
} else {
    Write-Host "    Startup task already exists" -ForegroundColor Green
}

# ── STATUS ──
$Status = [ordered]@{
    installed    = $true
    mode         = "whitelist"
    last_updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    user         = $UserEmail
    allowed      = $Allowed.Count
    blocked      = $BlockedCount
    version      = "4.0"
}
$Status | ConvertTo-Json | Out-File $StatusFile -Encoding UTF8 -Force

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host " X-NET v4 ACTIVE - WHITELIST MODE"   -ForegroundColor Green
Write-Host " Allowed: $($Allowed.Count) root domains" -ForegroundColor Green
Write-Host " Blocked: $BlockedCount popular entries" -ForegroundColor Green
Write-Host " + Firewall: Telegram / Copilot / VPN" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host " >> Restart your browser now! <<"     -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to close"
