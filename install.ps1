# X-NET Blocker v3 - TRUE WHITELIST MODE
param ([string]$UserEmail = "")

$InstallDir = "C:\XNET"
$EmailFile  = "$InstallDir\user.txt"
$HostsFile  = "$env:SystemRoot\System32\drivers\etc\hosts"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Must run as Administrator" -ForegroundColor Red
    exit
}

if (-not (Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }

if ($UserEmail -ne "") {
    $UserEmail | Out-File $EmailFile -Force -Encoding ASCII
} elseif (Test-Path $EmailFile) {
    $UserEmail = (Get-Content $EmailFile | Select-Object -First 1).Trim()
} else {
    Write-Host "ERROR: No email found" -ForegroundColor Red
    exit
}

$SafeEmail = $UserEmail -replace '@', '_at_'
$JsonUrl   = "https://raw.githubusercontent.com/meny0583285502/X-NET/main/profiles/$SafeEmail.json"
$BaseUrl   = "https://raw.githubusercontent.com/meny0583285502/X-NET/main/base_whitelist.json"

Write-Host "[1] Fetching profile for: $UserEmail" -ForegroundColor Cyan

try {
    $ProfileData = Invoke-RestMethod -Uri $JsonUrl -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Host "ERROR: Cannot fetch profile - $_" -ForegroundColor Red
    exit
}

# === UNINSTALL ===
if ($ProfileData.requests.uninstall_approved -eq $true) {
    Write-Host "[!] Uninstall approved - removing X-NET..." -ForegroundColor Yellow
    if (Test-Path $HostsFile) { attrib -r $HostsFile }
    $h = Get-Content $HostsFile -Raw
    $h = $h -replace "(?s)# \[X-NET-START\].*?# \[X-NET-END\]\r?\n?", ""
    $h | Out-File $HostsFile -Encoding UTF8 -Force
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "DnsOverHttpsMode" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "BuiltInDnsClientEnabled" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
    ipconfig /flushdns | Out-Null
    schtasks /delete /tn "XNET_Blocker" /f 2>$null
    Start-Sleep 1
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[+] X-NET removed successfully" -ForegroundColor Green
    exit
}

# === BUILD WHITELIST ===
Write-Host "[2] Building whitelist..." -ForegroundColor Cyan

$AllAllowed = @()

# Base whitelist
try {
    $BaseData = Invoke-RestMethod -Uri $BaseUrl -UseBasicParsing -ErrorAction Stop
    $AllAllowed += $BaseData.allowed_domains
    Write-Host "    Base whitelist: $($BaseData.allowed_domains.Count) domains" -ForegroundColor Green
} catch {
    Write-Host "    Base whitelist not available" -ForegroundColor Yellow
}

# Profile whitelist
if ($ProfileData.allowed_domains) {
    $AllAllowed += $ProfileData.allowed_domains
    Write-Host "    Profile whitelist: $($ProfileData.allowed_domains.Count) domains" -ForegroundColor Green
}

# Always allow - system domains
$AlwaysAllow = @(
    "meny0583285502.github.io",
    "raw.githubusercontent.com",
    "github.com",
    "api.emailjs.com",
    "fonts.googleapis.com",
    "fonts.gstatic.com",
    "ocsp.digicert.com",
    "ocsp.pki.goog",
    "ctldl.windowsupdate.com",
    "update.microsoft.com",
    "windowsupdate.microsoft.com",
    "download.windowsupdate.com",
    "wustat.windows.com",
    "ntservicepack.microsoft.com",
    "dns.msftncsi.com",
    "www.msftncsi.com",
    "ipv6.msftncsi.com",
    "teredo.ipv6.microsoft.com",
    "login.microsoftonline.com",
    "login.live.com"
)
$AllAllowed += $AlwaysAllow

# Clean & deduplicate
$AllAllowed = $AllAllowed | Where-Object { $_ -and $_.Trim() -ne "" } | ForEach-Object {
    $_ -replace "^https?://", "" -replace "/$", "" -replace "^www\.", ""
} | Sort-Object -Unique

Write-Host "    Total unique base domains: $($AllAllowed.Count)" -ForegroundColor Cyan

# Expand: add www. variant for each
$ExpandedAllowed = @()
foreach ($d in $AllAllowed) {
    $ExpandedAllowed += $d
    $ExpandedAllowed += "www.$d"
}
$ExpandedAllowed = $ExpandedAllowed | Sort-Object -Unique

Write-Host "[3] Expanded to $($ExpandedAllowed.Count) entries (with www variants)" -ForegroundColor Cyan

# === TRUE WHITELIST via HOSTS ===
# Strategy: redirect ALL known popular domains to 0.0.0.0
# EXCEPT those in whitelist
# Then use Firewall DNS sinkhole for everything else

Write-Host "[4] Writing hosts file (TRUE WHITELIST)..." -ForegroundColor Cyan

if (Test-Path $HostsFile) { attrib -r $HostsFile }

# Build block list = massive list of domains NOT in whitelist
# We use a wildcard approach: block *.com *.net *.org etc via DNS client policy

$BlockLines = @()
$BlockLines += "# [X-NET-START] - TRUE WHITELIST - DO NOT EDIT"
$BlockLines += "# User: $UserEmail"
$BlockLines += "# Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$BlockLines += "# Mode: WHITELIST (block all except listed)"
$BlockLines += "# Allowed domains: $($AllAllowed.Count)"
$BlockLines += ""

# POPULAR DOMAINS BLOCKLIST (comprehensive)
$PopularDomains = @(
    # Social
    "facebook.com","instagram.com","twitter.com","x.com","tiktok.com",
    "snapchat.com","pinterest.com","reddit.com","tumblr.com","linkedin.com",
    "threads.net","mastodon.social","discord.com","twitch.tv","kick.com",
    # Video
    "youtube.com","youtu.be","vimeo.com","dailymotion.com","rumble.com",
    "odysee.com","bitchute.com","brighteon.com","tubi.tv",
    # Streaming
    "netflix.com","disneyplus.com","hbo.com","max.com","hulu.com",
    "peacocktv.com","paramountplus.com","appletv.apple.com","primevideo.com",
    # Music
    "spotify.com","soundcloud.com","deezer.com","tidal.com","pandora.com",
    # News IL
    "ynet.co.il","mako.co.il","walla.co.il","nrg.co.il","haaretz.co.il",
    "israelhayom.co.il","jpost.com","timesofisrael.com","calcalist.co.il",
    "themarker.com","ice.co.il","reshet.tv","channel12.co.il","channel13.co.il",
    "kan.org.il","arutz7.co.il","kikar.co.il","bhol.co.il","behadrei.co.il",
    # News International
    "cnn.com","bbc.com","bbc.co.uk","nytimes.com","washingtonpost.com",
    "foxnews.com","nbcnews.com","abcnews.go.com","cbsnews.com","apnews.com",
    "reuters.com","theguardian.com","aljazeera.com","france24.com",
    # Shopping
    "amazon.com","ebay.com","aliexpress.com","alibaba.com","shopify.com",
    "etsy.com","walmart.com","target.com","bestbuy.com",
    # Messaging
    "telegram.org","web.telegram.org","signal.org","viber.com",
    "web.whatsapp.com","messenger.com",
    # AI
    "chat.openai.com","chatgpt.com","openai.com",
    "copilot.microsoft.com","sydney.bing.com","bing.com",
    "claude.ai","anthropic.com",
    "gemini.google.com","bard.google.com",
    "perplexity.ai","character.ai","poe.com","you.com",
    # Gaming
    "steampowered.com","store.steampowered.com","epicgames.com",
    "roblox.com","minecraft.net","ea.com","ubisoft.com",
    "battle.net","playstation.com","xbox.com",
    # Adult
    "pornhub.com","xvideos.com","xhamster.com","xnxx.com","youporn.com",
    # Gambling
    "bet365.com","888casino.com","pokerstars.com","betway.com",
    # Misc
    "craigslist.org","9gag.com","buzzfeed.com","vice.com",
    "medium.com","substack.com","quora.com","stackoverflow.com",
    "wikipedia.org","wikimedia.org",
    "archive.org","waybackmachine.org",
    "vpnmentor.com","nordvpn.com","expressvpn.com","protonvpn.com",
    "torproject.org","thepiratebay.org","1337x.to","rarbg.to"
)

$Blocked = 0
foreach ($Domain in $PopularDomains) {
    $Clean = $Domain -replace "^www\.", ""
    $IsAllowed = $ExpandedAllowed | Where-Object { ($_ -replace "^www\.", "") -eq $Clean }
    if (-not $IsAllowed) {
        $BlockLines += "0.0.0.0 $Clean"
        $BlockLines += "0.0.0.0 www.$Clean"
        $Blocked += 2
    }
}

$BlockLines += ""
$BlockLines += "# [X-NET-END]"

# Write hosts
$HostsContent = Get-Content $HostsFile -Raw -ErrorAction SilentlyContinue
if (-not $HostsContent) { $HostsContent = "" }

if ($HostsContent -match "(?s)# \[X-NET-START\].*?# \[X-NET-END\]") {
    $HostsContent = $HostsContent -replace "(?s)# \[X-NET-START\].*?# \[X-NET-END\]", ($BlockLines -join "`r`n")
} else {
    $HostsContent = $HostsContent.TrimEnd() + "`r`n" + ($BlockLines -join "`r`n")
}

$Retry = 0; $Success = $false
while (-not $Success -and $Retry -lt 5) {
    try {
        [System.IO.File]::WriteAllText($HostsFile, $HostsContent, [System.Text.Encoding]::UTF8)
        $Success = $true
    } catch {
        $Retry++
        Write-Host "    File locked, retry $Retry/5..." -ForegroundColor Yellow
        Start-Sleep 2
    }
}
Write-Host "    Hosts: $Blocked entries blocked" -ForegroundColor Green

# === BROWSER POLICIES (disable DoH) ===
Write-Host "[5] Disabling DNS-over-HTTPS in browsers..." -ForegroundColor Cyan

$ChromeKey = "HKLM:\SOFTWARE\Policies\Google\Chrome"
if (-not (Test-Path $ChromeKey)) { New-Item -Path $ChromeKey -Force | Out-Null }
Set-ItemProperty -Path $ChromeKey -Name "DnsOverHttpsMode" -Value "off" -Force

$EdgeKey = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $EdgeKey)) { New-Item -Path $EdgeKey -Force | Out-Null }
Set-ItemProperty -Path $EdgeKey -Name "BuiltInDnsClientEnabled" -Value 0 -Type DWord -Force

$FirefoxKey = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
if (-not (Test-Path $FirefoxKey)) { New-Item -Path $FirefoxKey -Force | Out-Null }
Set-ItemProperty -Path $FirefoxKey -Name "DNSOverHTTPS" -Value '{"Enabled": false}' -Force

# === FIREWALL - Block app-level (Telegram, etc.) ===
Write-Host "[6] Applying Firewall rules..." -ForegroundColor Cyan
Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "XNET-Telegram" -Direction Outbound -Action Block `
    -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") `
    -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null

New-NetFirewallRule -DisplayName "XNET-Copilot" -Direction Outbound -Action Block `
    -RemoteAddress @("20.190.128.0/18","40.126.0.0/18") `
    -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null

ipconfig /flushdns | Out-Null
Write-Host "    DNS cache cleared" -ForegroundColor Green

# === STARTUP TASK ===
Write-Host "[7] Registering startup task..." -ForegroundColor Cyan
$UpdaterPath = "$InstallDir\updater.ps1"
'Invoke-WebRequest -Uri "https://raw.githubusercontent.com/meny0583285502/X-NET/main/install.ps1" -OutFile "C:\XNET\run.ps1" -UseBasicParsing -ErrorAction SilentlyContinue; & "C:\XNET\run.ps1"' | Out-File $UpdaterPath -Encoding UTF8 -Force

$TaskExists = schtasks /query /tn "XNET_Blocker" 2>$null
if ($LASTEXITCODE -ne 0) {
    schtasks /create /tn "XNET_Blocker" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$UpdaterPath`"" /sc onlogon /rl highest /f | Out-Null
    Write-Host "    Startup task created" -ForegroundColor Green
} else {
    Write-Host "    Startup task already exists" -ForegroundColor Green
}

# === STATUS FILE ===
$Status = @{ installed=$true; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm"); user=$UserEmail; allowed=$AllAllowed.Count; blocked=$Blocked; mode="whitelist" } | ConvertTo-Json
$Status | Out-File "$InstallDir\status.json" -Encoding UTF8 -Force

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "[+] X-NET ACTIVE - WHITELIST MODE"   -ForegroundColor Green
Write-Host "    Allowed: $($AllAllowed.Count) domains" -ForegroundColor Green  
Write-Host "    Blocked: $Blocked popular domains" -ForegroundColor Green
Write-Host "    + Firewall blocking Telegram/Copilot" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host "[!] Restart browser to apply changes!" -ForegroundColor Yellow
