# X-NET v10.0 - Full Fix (Re-resolve + Tray Timer + Sync Always Recreated)
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
if (-not $Silent) { Write-Host "===== X-NET v10.0 | $UserEmail =====" -ForegroundColor Cyan }

# ==========================================
# 0. שחזור DNS לפני fetch (כדי שיהיה אינטרנט)
# ==========================================
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
}
ipconfig /flushdns | Out-Null
Start-Sleep 2

# שליפת פרופיל המשתמש מ-GitHub
try {
    $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop
} catch {
    if (-not $Silent) { Write-Host "ERROR: Failed to pull profile from GitHub." -ForegroundColor Red; Read-Host }
    exit
}

# ==========================================
# 1. הסרה מלאה
# ==========================================
if ($P.requests.uninstall_approved -eq $true) {
    if (-not $Silent) { Write-Host "[!] Uninstalling X-NET..." -ForegroundColor Yellow }

    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
    schtasks /delete /tn "XNET_Blocker" /f 2>$null | Out-Null

    Get-WmiObject Win32_Process -Filter "name='powershell.exe'" |
        Where-Object { $_.CommandLine -match "tray.ps1" -or $_.CommandLine -match "sync.ps1" } |
        ForEach-Object { $_.Terminate() }

    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
    }
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
        Write-Host "[+] Removed Successfully." -ForegroundColor Green
        Read-Host "Press Enter to exit"
    }
    exit
}

# ==========================================
# 2. השהיה זמנית
# ==========================================
if ($null -ne $P.requests.pause -and $null -ne $P.requests.pause.until) {
    try {
        $UntilUTC = [datetime]::Parse($P.requests.pause.until).ToUniversalTime()
        if ((Get-Date).ToUniversalTime() -lt $UntilUTC) {
            Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
                Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
            }
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
# 3. בניית Whitelist
# ==========================================
$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

# שירותי בסיס של גוגל תמיד מורשים (לכניסה לאתר וכו')
[void]$Allowed.Add("googleapis.com")
[void]$Allowed.Add("gstatic.com")
[void]$Allowed.Add("accounts.google.com")
[void]$Allowed.Add("googleusercontent.com")

# רשימת Base (אם מופעל)
if ($P.base_sites_enabled -eq $true) {
    try {
        $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop
        $Base.allowed_domains | ForEach-Object {
            $d = ($_ -split '\|')[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""
            [void]$Allowed.Add($d)
        }
    } catch {}
}

# חיפוש גוגל (אם מופעל)
if ($P.google_search_enabled -eq $true) {
    [void]$Allowed.Add("google.com")
    [void]$Allowed.Add("google.co.il")
}

# דומיינים אישיים של המשתמש
if ($P.allowed_domains) {
    $P.allowed_domains | ForEach-Object {
        $d = ($_ -split '\|')[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""
        [void]$Allowed.Add($d)
    }
}

# דומיינים קריטיים של המערכת (תמיד מורשים)
@(
    "meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com",
    "api.emailjs.com",
    "update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com",
    "ctldl.windowsupdate.com","wustat.windows.com","dns.msftncsi.com",
    "login.microsoftonline.com","login.live.com","microsoft.com","office.com",
    "ocsp.digicert.com","ocsp.pki.goog","crl.microsoft.com","pki.goog"
) | ForEach-Object { [void]$Allowed.Add($_) }

# ==========================================
# 4. Resolve IP — עם retry לכל דומיין
# ==========================================
if (-not $Silent) { Write-Host "[+] Resolving IPs (using ISP DNS)..." -ForegroundColor Yellow }

# המתן קצת כדי שה-DNS יהיה זמין לאחר איפוס
Start-Sleep -Seconds 3

$HostLines = [System.Collections.Generic.List[string]]::new()
$ok = 0

foreach ($root in $Allowed) {
    $variants = @($root)
    if (-not $root.StartsWith("www.")) { $variants += "www.$root" }

    foreach ($v in $variants) {
        $resolved = $false
        # ניסיון resolve פעמיים (retry) — פותר את בעיית "לא התעדכן"
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            try {
                $ips = [Net.Dns]::GetHostAddresses($v) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
                if ($ips) {
                    foreach ($ip in $ips) {
                        $HostLines.Add("$($ip.IPAddressToString)`t$v")
                    }
                    $ok++
                    $resolved = $true
                    break
                }
            } catch {}
            if (-not $resolved -and $attempt -eq 1) { Start-Sleep -Milliseconds 500 }
        }
    }
}

if (-not $Silent) { Write-Host "[+] Resolved $ok domains." -ForegroundColor Green }

# ==========================================
# 5. נעילת DNS + Firewall
# ==========================================
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    $name = $_.Name; $idx = $_.InterfaceIndex
    try {
        Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue
        netsh interface ipv6 set dnsservers name="$name" static ::1 primary 2>&1 | Out-Null
    } catch {}
}
Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled } |
    ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue }

# כתיבת hosts
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
[IO.File]::WriteAllText($HOSTS, $existing.TrimEnd() + "`r`n" + ($block -join "`r`n"), [Text.Encoding]::UTF8)

# חסימת DoH בדפדפנים
$k = "HKLM:\SOFTWARE\Policies\Google\Chrome"
if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force
Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force

$k = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force
Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force

$k = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "DNSOverHTTPS" '{"Enabled": false}' -Force

# חוקי Firewall
Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "XNET-Telegram"   -Direction Outbound -Action Block -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-VPN-UDP"    -Direction Outbound -Action Block -Protocol UDP -RemotePort @(1194,51820) -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "XNET-Block-QUIC" -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Profile Any -ErrorAction SilentlyContinue | Out-Null

ipconfig /flushdns | Out-Null

# ==========================================
# 6. Tray Icon — עם Timer שמתעדכן כל 30 שניות
# ==========================================
$TrayCode = @'
$mutex = New-Object System.Threading.Mutex($false, "Global\XNET_TRAY_MUTEX")
if (-not $mutex.WaitOne(0, $false)) { exit }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Shield
$notify.Visible = $true
$notify.Text = "X-NET - טוען..."

# קריאת status.json והצגת מידע ב-tooltip
function Update-TrayTooltip {
    $statusFile = "C:\XNET\status.json"
    if (Test-Path $statusFile) {
        try {
            $s = Get-Content $statusFile -Raw | ConvertFrom-Json
            $lastUpdate = $s.last_updated
            $allowedCount = $s.allowed
            $user = $s.user
            $msg = "X-NET פעיל | $user`n$allowedCount דומיינים | עודכן: $lastUpdate"
            # NotifyIcon.Text מוגבל ל-63 תווים
            if ($msg.Length -gt 63) { $msg = $msg.Substring(0, 60) + "..." }
            $notify.Text = $msg
        } catch {
            $notify.Text = "X-NET פעיל"
        }
    } else {
        $notify.Text = "X-NET פעיל"
    }
}

# ContextMenu עם כפתור רענון
$menu = New-Object System.Windows.Forms.ContextMenu
$refreshItem = New-Object System.Windows.Forms.MenuItem "🔄 רענן עכשיו"
$refreshItem.add_Click({
    $notify.Text = "X-NET - מרענן..."
    $emailFile = "C:\XNET\user.txt"
    if (Test-Path $emailFile) {
        $email = (Get-Content $emailFile -First 1).Trim()
        Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\XNET\install.ps1`" -UserEmail `"$email`" -Silent" -Verb RunAs -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 8
    Update-TrayTooltip
})
$exitItem = New-Object System.Windows.Forms.MenuItem "❌ סגור Tray"
$exitItem.add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() })
$menu.MenuItems.Add($refreshItem) | Out-Null
$menu.MenuItems.Add($exitItem) | Out-Null
$notify.ContextMenu = $menu

# Double-click פותח את דף הניהול
$notify.add_DoubleClick({
    $emailFile = "C:\XNET\user.txt"
    $email = ""
    if (Test-Path $emailFile) { $email = (Get-Content $emailFile -First 1).Trim() }
    Start-Process "https://meny0583285502.github.io/X-NET/?user=$email"
})

# Timer — מתעדכן כל 30 שניות
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000
$timer.add_Tick({ Update-TrayTooltip })
$timer.Start()
Update-TrayTooltip

$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.WindowState = "Minimized"
[System.Windows.Forms.Application]::Run($form)
'@

$TrayCode | Out-File "$DIR\tray.ps1" -Encoding UTF8 -Force

# Shortcut להפעלה עם Startup
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$Shortcut.Save()

# הרג tray ישן והפעלה מחדש
Get-WmiObject Win32_Process -Filter "name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "tray.ps1" } |
    ForEach-Object { $_.Terminate() }
Start-Sleep 1
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`"" -ErrorAction SilentlyContinue

# ==========================================
# 7. Sync Task — תמיד נמחק ונוצר מחדש!
#    (זה הפיקס המרכזי — מבטיח שה-task תמיד עדכני)
# ==========================================
$SyncTask = "$DIR\sync.ps1"

# sync.ps1 — מוריד install.ps1 עדכני ומריץ אותו
@"
try {
    Invoke-WebRequest '$GH_RAW/install.ps1' -OutFile '$DIR\install.ps1' -UseBasicParsing -ErrorAction Stop
    & '$DIR\install.ps1' -UserEmail '$UserEmail' -Silent
} catch {
    # אם ה-download נכשל, הרץ את הגרסה המקומית
    if (Test-Path '$DIR\install.ps1') {
        & '$DIR\install.ps1' -UserEmail '$UserEmail' -Silent
    }
}
"@ | Out-File $SyncTask -Encoding UTF8 -Force

# מחק תמיד — ואז צור מחדש (הפיקס!)
schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
schtasks /create /tn "XNET_Sync" `
    /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SyncTask`"" `
    /sc minute /mo 5 `
    /ru "SYSTEM" /f 2>&1 | Out-Null

if (-not $Silent) { Write-Host "[+] Sync Task created (every 5 minutes)." -ForegroundColor Green }

# ==========================================
# 8. שמירת status.json (לשימוש ה-Tray)
# ==========================================
@{
    installed    = $true
    mode         = "whitelist"
    base_sites_enabled   = $P.base_sites_enabled
    google_search_enabled = $P.google_search_enabled
    last_updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    user         = $UserEmail
    allowed      = $Allowed.Count
    version      = "10.0"
} | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force

if (-not $Silent) {
    Write-Host "[+] Done! $($Allowed.Count) domains allowed." -ForegroundColor Green
    Start-Process "https://meny0583285502.github.io/X-NET/?user=$UserEmail&installed=1"
    Start-Sleep 1
    exit
}
