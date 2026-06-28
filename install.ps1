# X-NET v11.0 — ארכיטקטורה חדשה: התקנה חד פעמית + sync.ps1 עצמאי
# install.ps1 רץ פעם אחת (התקנה / עדכון ידני). 
# sync.ps1 הוא זה שרץ כל דקה ועושה את כל עבודת הסינון.
param([string]$UserEmail = "", [switch]$Silent)

$VERSION = "11.0"
$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"

if (-not (Test-Path $DIR)) { New-Item $DIR -ItemType Directory -Force | Out-Null }

# שמירת / קריאת אימייל
$EmailFile = "$DIR\user.txt"
if ($UserEmail) { $UserEmail | Out-File $EmailFile -Encoding UTF8 -Force }
elseif (Test-Path $EmailFile) { $UserEmail = (Get-Content $EmailFile -First 1).Trim() }
else { if (-not $Silent) { Write-Host "ERROR: No email"; Read-Host }; exit }

if (-not $Silent) { Write-Host "===== X-NET v$VERSION | $UserEmail =====" -ForegroundColor Cyan }

# ==========================================
# שלב 1: כתיבת sync.ps1 — הלב של המערכת
# sync.ps1 הוא הסקריפט שרץ כל דקה.
# הוא עצמאי לחלוטין — לא תלוי ב-install.ps1.
# ==========================================
$SyncScript = @'
# X-NET sync.ps1 — רץ כל דקה כ-SYSTEM
$DIR    = "C:\XNET"
$HOSTS  = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"

$EmailFile = "$DIR\user.txt"
if (-not (Test-Path $EmailFile)) { exit }
$UserEmail = (Get-Content $EmailFile -First 1).Trim()
$Safe = $UserEmail -replace '@','_at_' -replace '\.','_dot_'

# ── שלב א: שחרר DNS כדי שנוכל לגשת לאינטרנט ──
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
}
ipconfig /flushdns | Out-Null
Start-Sleep -Seconds 2

# ── שלב ב: משוך פרופיל מ-GitHub ──
try {
    $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop
} catch {
    # אם נכשל — שמור DNS פתוח ונסה שוב בדקה הבאה
    exit
}

# ── שלב ג: הסרה מלאה ──
if ($P.requests.uninstall_approved -eq $true) {
    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
    Get-WmiObject Win32_Process -Filter "name='powershell.exe'" |
        Where-Object { $_.CommandLine -match "tray.ps1" } |
        ForEach-Object { $_.Terminate() }
    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue
    }
    attrib -r $HOSTS 2>$null
    $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue
    if ($h) { [IO.File]::WriteAllText($HOSTS, ($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""), [Text.Encoding]::UTF8) }
    "HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox" | ForEach-Object {
        Remove-ItemProperty $_ -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -ErrorAction SilentlyContinue
    }
    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue
    ipconfig /flushdns | Out-Null
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk" -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    Remove-Item $DIR -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

# ── שלב ד: השהיה זמנית ──
if ($P.requests.pause -and $P.requests.pause.until) {
    try {
        $until = [datetime]::Parse($P.requests.pause.until).ToUniversalTime()
        if ((Get-Date).ToUniversalTime() -lt $until) {
            # השהיה פעילה — השאר DNS פתוח, נקה hosts, צא
            attrib -r $HOSTS 2>$null
            $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue
            if ($h) { [IO.File]::WriteAllText($HOSTS, ($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""), [Text.Encoding]::UTF8) }
            ipconfig /flushdns | Out-Null
            # עדכן status
            @{ paused=$true; paused_until=$P.requests.pause.until; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail } |
                ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force
            exit
        }
    } catch {}
}

# ── שלב ה: בנה רשימת דומיינים מורשים ──
$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

# קריטיים תמיד
@("googleapis.com","gstatic.com","accounts.google.com","googleusercontent.com",
  "meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com",
  "api.emailjs.com","update.microsoft.com","windowsupdate.microsoft.com",
  "download.windowsupdate.com","ctldl.windowsupdate.com","wustat.windows.com",
  "dns.msftncsi.com","login.microsoftonline.com","login.live.com","microsoft.com",
  "office.com","ocsp.digicert.com","ocsp.pki.goog","crl.microsoft.com","pki.goog"
) | ForEach-Object { [void]$Allowed.Add($_) }

# base whitelist
if ($P.base_sites_enabled -eq $true) {
    try {
        $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop
        $Base.allowed_domains | ForEach-Object {
            $d = ($_ -split '\|')[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""
            [void]$Allowed.Add($d)
        }
    } catch {}
}

# גוגל
if ($P.google_search_enabled -eq $true) { [void]$Allowed.Add("google.com"); [void]$Allowed.Add("google.co.il") }

# אישי
if ($P.allowed_domains) {
    $P.allowed_domains | ForEach-Object {
        $d = ($_ -split '\|')[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""
        [void]$Allowed.Add($d)
    }
}

# ── שלב ו: כתוב whitelist.txt ──
# זה הקובץ שממנו נעשה Resolve. DNS עדיין פתוח כאן!
$AllowedList = $Allowed | Sort-Object
$AllowedList | Out-File "$DIR\whitelist.txt" -Encoding UTF8 -Force

# ── שלב ז: Resolve — DNS עדיין פתוח! ──
Start-Sleep -Seconds 1  # וודא שה-DNS התייצב
$HostLines = [System.Collections.Generic.List[string]]::new()
$ok = 0

foreach ($root in $AllowedList) {
    $variants = @($root)
    if (-not $root.StartsWith("www.")) { $variants += "www.$root" }
    foreach ($v in $variants) {
        try {
            $ips = [Net.Dns]::GetHostAddresses($v) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
            foreach ($ip in $ips) { $HostLines.Add("$($ip.IPAddressToString)`t$v") }
            $ok++
        } catch {}
    }
}

# ── שלב ח: נעל DNS ל-127.0.0.1 ──
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue } catch {}
}
Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled } |
    ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue }

# חסימת DoH בדפדפנים
foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force
    Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force
}
$k = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k "DNSOverHTTPS" '{"Enabled": false}' -Force

# ── שלב ט: כתוב hosts ──
attrib -r $HOSTS 2>$null
$block = [System.Collections.Generic.List[string]]::new()
$block.Add("# [XNET] DO NOT EDIT — managed by X-NET sync")
$block.Add("# Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | User: $UserEmail | Domains: $ok")
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

# Firewall (רק אם לא קיים)
$fw = Get-NetFirewallRule -DisplayName "XNET-Telegram" -ErrorAction SilentlyContinue
if (-not $fw) {
    New-NetFirewallRule -DisplayName "XNET-Telegram"   -Direction Outbound -Action Block -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "XNET-VPN-UDP"    -Direction Outbound -Action Block -Protocol UDP -RemotePort @(1194,51820) -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "XNET-Block-QUIC" -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Profile Any -ErrorAction SilentlyContinue | Out-Null
}

ipconfig /flushdns | Out-Null

# ── שלב י: עדכן status.json ──
@{
    installed=$true; paused=$false; mode="whitelist"
    base_sites_enabled=$P.base_sites_enabled
    google_search_enabled=$P.google_search_enabled
    last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    user=$UserEmail; allowed=$ok; version="11.0"
} | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force
'@

$SyncScript | Out-File "$DIR\sync.ps1" -Encoding UTF8 -Force
if (-not $Silent) { Write-Host "[+] sync.ps1 written." -ForegroundColor Green }

# ==========================================
# שלב 2: Tray icon — עם כפתור רענון שמפעיל sync.ps1
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

function Run-Sync {
    $syncFile = "C:\XNET\sync.ps1"
    if (Test-Path $syncFile) {
        Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$syncFile`"" -Verb RunAs -ErrorAction SilentlyContinue
    }
}

function Update-Tray {
    $f = "C:\XNET\status.json"
    if (Test-Path $f) {
        try {
            $s = Get-Content $f -Raw | ConvertFrom-Json
            if ($s.paused) {
                $notify.Icon = [System.Drawing.SystemIcons]::Warning
                $t = "X-NET — מושהה | " + $s.paused_until
            } else {
                $notify.Icon = [System.Drawing.SystemIcons]::Shield
                $t = "X-NET פעיל | " + $s.allowed + " דומיינים | " + $s.last_updated
            }
            if ($t.Length -gt 63) { $t = $t.Substring(0,60) + "..." }
            $notify.Text = $t
        } catch { $notify.Text = "X-NET פעיל" }
    }
}

$menu = New-Object System.Windows.Forms.ContextMenu

$refreshItem = New-Object System.Windows.Forms.MenuItem "🔄 רענן עכשיו"
$refreshItem.add_Click({
    $notify.Text = "X-NET - מרענן..."
    Run-Sync
    Start-Sleep -Seconds 12
    Update-Tray
})

$openItem = New-Object System.Windows.Forms.MenuItem "🌐 פתח דשבורד"
$openItem.add_Click({
    $e = ""
    if (Test-Path "C:\XNET\user.txt") { $e = (Get-Content "C:\XNET\user.txt" -First 1).Trim() }
    Start-Process "https://meny0583285502.github.io/X-NET/?user=$e"
})

$exitItem = New-Object System.Windows.Forms.MenuItem "❌ סגור Tray"
$exitItem.add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() })

$menu.MenuItems.Add($refreshItem) | Out-Null
$menu.MenuItems.Add($openItem)    | Out-Null
$menu.MenuItems.Add("-")          | Out-Null
$menu.MenuItems.Add($exitItem)    | Out-Null
$notify.ContextMenu = $menu

$notify.add_DoubleClick({
    $e = ""
    if (Test-Path "C:\XNET\user.txt") { $e = (Get-Content "C:\XNET\user.txt" -First 1).Trim() }
    Start-Process "https://meny0583285502.github.io/X-NET/?user=$e"
})

# Timer: כל 30 שניות מעדכן את ה-tooltip
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000
$timer.add_Tick({ Update-Tray })
$timer.Start()
Update-Tray

$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.WindowState = "Minimized"
[System.Windows.Forms.Application]::Run($form)
'@

$TrayCode | Out-File "$DIR\tray.ps1" -Encoding UTF8 -Force

# Shortcut להפעלה עם סטארטאפ
$WshShell = New-Object -ComObject WScript.Shell
$sc = $WshShell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$sc.TargetPath = "powershell.exe"
$sc.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$sc.Save()

# הרג tray ישן → הפעל חדש
Get-WmiObject Win32_Process -Filter "name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "tray\.ps1" } |
    ForEach-Object { $_.Terminate() }
Start-Sleep 1
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`"" -ErrorAction SilentlyContinue

if (-not $Silent) { Write-Host "[+] Tray started." -ForegroundColor Green }

# ==========================================
# שלב 3: Scheduled Task — מריץ sync.ps1 כל דקה
# (תמיד מוחק ומחדש — לא סומכים על קיים)
# ==========================================
schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
schtasks /create /tn "XNET_Sync" `
    /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\sync.ps1`"" `
    /sc minute /mo 1 `
    /ru "SYSTEM" /f 2>&1 | Out-Null

if (-not $Silent) { Write-Host "[+] Scheduled Task: every 1 minute." -ForegroundColor Green }

# ==========================================
# שלב 4: הפעל sync.ps1 עכשיו (נועל מיד)
# ==========================================
if (-not $Silent) { Write-Host "[+] Running first sync now..." -ForegroundColor Yellow }
& "$DIR\sync.ps1"

if (-not $Silent) {
    Write-Host "[+] Done! X-NET v$VERSION active." -ForegroundColor Green
    Start-Process "https://meny0583285502.github.io/X-NET/?user=$UserEmail&installed=1"
    Start-Sleep 1
}
