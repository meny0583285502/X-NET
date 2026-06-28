# X-NET v11.3 - install.ps1
param([string]$UserEmail = "", [switch]$Silent)

$VERSION = "11.3"
$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"

# --- הבטח הרשאות Admin ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Re-launching as Administrator..." -ForegroundColor Yellow
    $args2 = "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    if ($UserEmail) { $args2 += " -UserEmail `"$UserEmail`"" }
    Start-Process powershell -ArgumentList $args2 -Verb RunAs
    exit
}

# --- צור תיקיה עם אימות ---
Write-Host "Creating C:\XNET..." -ForegroundColor Cyan
try {
    if (Test-Path $DIR) {
        Write-Host "  Directory already exists." -ForegroundColor Gray
    } else {
        New-Item -Path $DIR -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Host "  Created OK." -ForegroundColor Green
    }
    # בדיקת כתיבה
    [IO.File]::WriteAllText("$DIR\test.txt", "ok", [Text.Encoding]::UTF8)
    Remove-Item "$DIR\test.txt" -Force
    Write-Host "  Write test OK." -ForegroundColor Green
} catch {
    Write-Host "FATAL: Cannot create/write to C:\XNET" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

# --- אימייל ---
$EmailFile = "$DIR\user.txt"
if ($UserEmail)               { $UserEmail | Out-File $EmailFile -Encoding UTF8 -Force }
elseif (Test-Path $EmailFile) { $UserEmail = (Get-Content $EmailFile -First 1).Trim() }
else {
    $UserEmail = Read-Host "Enter your email"
    $UserEmail | Out-File $EmailFile -Encoding UTF8 -Force
}

Write-Host "===== X-NET v$VERSION | $UserEmail =====" -ForegroundColor Cyan

# ==================================================
# sync.ps1 - שורה-שורה
# ==================================================
Write-Host "Writing sync.ps1..." -ForegroundColor Yellow
$S = [System.Collections.Generic.List[string]]::new()
$S.Add('$DIR    = "C:\XNET"')
$S.Add('$LOG    = "$DIR\sync_log.txt"')
$S.Add('$HOSTS  = "$env:SystemRoot\System32\drivers\etc\hosts"')
$S.Add('$GH_RAW = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"')
$S.Add('function Log($msg) { "$(Get-Date -Format ''HH:mm:ss'') $msg" | Out-File $LOG -Append -Encoding UTF8 }')
$S.Add('if (-not (Test-Path "$DIR\user.txt")) { exit }')
$S.Add('$UserEmail = (Get-Content "$DIR\user.txt" -First 1).Trim()')
$S.Add('$Safe = $UserEmail -replace "@","_at_" -replace "\.","_dot_"')
$S.Add('Log "=== Sync start | $UserEmail ==="')
$S.Add('# 1. Release DNS')
$S.Add('Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {')
$S.Add('    Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue')
$S.Add('}')
$S.Add('ipconfig /flushdns | Out-Null')
$S.Add('Start-Sleep -Seconds 2')
$S.Add('Log "DNS released"')
$S.Add('# 2. Fetch profile')
$S.Add('try {')
$S.Add('    $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop')
$S.Add('    Log "Profile OK: base=$($P.base_sites_enabled) google=$($P.google_search_enabled) domains=$($P.allowed_domains.Count)"')
$S.Add('} catch {')
$S.Add('    Log "ERROR fetching profile: $_"; exit')
$S.Add('}')
$S.Add('# 3. Uninstall?')
$S.Add('if ($P.requests.uninstall_approved -eq $true) {')
$S.Add('    Log "Uninstalling..."')
$S.Add('    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null')
$S.Add('    Get-WmiObject Win32_Process -Filter "name=''powershell.exe''" | Where-Object { $_.CommandLine -match "tray\.ps1" } | ForEach-Object { $_.Terminate() | Out-Null }')
$S.Add('    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue }')
$S.Add('    attrib -r $HOSTS 2>$null')
$S.Add('    $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue')
$S.Add('    if ($h) { [IO.File]::WriteAllText($HOSTS, ($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""), [Text.Encoding]::UTF8) }')
$S.Add('    foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox")) { Remove-ItemProperty $k -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -ErrorAction SilentlyContinue }')
$S.Add('    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue')
$S.Add('    ipconfig /flushdns | Out-Null')
$S.Add('    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk" -Force -ErrorAction SilentlyContinue')
$S.Add('    Start-Sleep 1; Remove-Item $DIR -Recurse -Force -ErrorAction SilentlyContinue')
$S.Add('    exit')
$S.Add('}')
$S.Add('# 4. Pause?')
$S.Add('if ($P.requests.pause -and $P.requests.pause.until) {')
$S.Add('    try {')
$S.Add('        $until = [datetime]::Parse($P.requests.pause.until).ToUniversalTime()')
$S.Add('        if ((Get-Date).ToUniversalTime() -lt $until) {')
$S.Add('            Log "PAUSED until $($P.requests.pause.until)"')
$S.Add('            attrib -r $HOSTS 2>$null')
$S.Add('            $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue')
$S.Add('            if ($h) { [IO.File]::WriteAllText($HOSTS, ($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""), [Text.Encoding]::UTF8) }')
$S.Add('            ipconfig /flushdns | Out-Null')
$S.Add('            @{ paused=$true; paused_until=$P.requests.pause.until; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')
$S.Add('            exit')
$S.Add('        }')
$S.Add('    } catch { Log "Pause parse error: $_" }')
$S.Add('}')
$S.Add('# 5. Build allowed list')
$S.Add('$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)')
$S.Add('$sys = "googleapis.com","gstatic.com","accounts.google.com","googleusercontent.com","meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com","api.emailjs.com","update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com","ctldl.windowsupdate.com","wustat.windows.com","dns.msftncsi.com","login.microsoftonline.com","login.live.com","microsoft.com","office.com","ocsp.digicert.com","ocsp.pki.goog","crl.microsoft.com","pki.goog"')
$S.Add('$sys | ForEach-Object { [void]$Allowed.Add($_) }')
$S.Add('if ($P.base_sites_enabled -eq $true) {')
$S.Add('    try {')
$S.Add('        $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop')
$S.Add('        $Base.allowed_domains | ForEach-Object { $d = ($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }')
$S.Add('        Log "Base loaded: $($Base.allowed_domains.Count)"')
$S.Add('    } catch { Log "Base error: $_" }')
$S.Add('}')
$S.Add('if ($P.google_search_enabled -eq $true) { [void]$Allowed.Add("google.com"); [void]$Allowed.Add("google.co.il"); Log "Google: ON" }')
$S.Add('if ($P.allowed_domains -and $P.allowed_domains.Count -gt 0) {')
$S.Add('    $P.allowed_domains | ForEach-Object { $d = ($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }')
$S.Add('    Log "Personal: $($P.allowed_domains.Count)"')
$S.Add('}')
$S.Add('Log "Total: $($Allowed.Count) domains"')
$S.Add('# 6. Save whitelist.txt + Resolve (DNS still open!)')
$S.Add('$AllowedList = $Allowed | Sort-Object')
$S.Add('$AllowedList | Out-File "$DIR\whitelist.txt" -Encoding UTF8 -Force')
$S.Add('$HostLines = [System.Collections.Generic.List[string]]::new()')
$S.Add('$ok = 0')
$S.Add('foreach ($root in $AllowedList) {')
$S.Add('    $variants = @($root); if (-not $root.StartsWith("www.")) { $variants += "www.$root" }')
$S.Add('    foreach ($v in $variants) {')
$S.Add('        try {')
$S.Add('            $ips = [Net.Dns]::GetHostAddresses($v) | Where-Object { $_.AddressFamily -eq "InterNetwork" }')
$S.Add('            foreach ($ip in $ips) { $HostLines.Add("$($ip.IPAddressToString)`t$v") }')
$S.Add('            $ok++')
$S.Add('        } catch {}')
$S.Add('    }')
$S.Add('}')
$S.Add('Log "Resolved: $ok / $($AllowedList.Count) -> $($HostLines.Count) entries"')
$S.Add('# 7. Lock DNS')
$S.Add('Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {')
$S.Add('    try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue } catch {}')
$S.Add('}')
$S.Add('Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled } | ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue }')
$S.Add('foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {')
$S.Add('    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }')
$S.Add('    Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force')
$S.Add('    Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force')
$S.Add('}')
$S.Add('$k = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"')
$S.Add('if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }')
$S.Add('Set-ItemProperty $k "DNSOverHTTPS" "{""Enabled"": false}" -Force')
$S.Add('Log "DNS locked"')
$S.Add('# 8. Write hosts')
$S.Add('attrib -r $HOSTS 2>$null')
$S.Add('$block = [System.Collections.Generic.List[string]]::new()')
$S.Add('$block.Add("# [XNET] DO NOT EDIT")')
$S.Add('$block.Add("# Updated: $(Get-Date -Format ''yyyy-MM-dd HH:mm:ss'') | Domains: $ok")')
$S.Add('$block.Add("127.0.0.1 localhost")')
$S.Add('$block.Add("::1 localhost")')
$S.Add('$block.Add("")')
$S.Add('foreach ($line in $HostLines) { $block.Add($line) }')
$S.Add('$block.Add("")')
$S.Add('$block.Add("# [/XNET]")')
$S.Add('$existing = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue; if (-not $existing) { $existing = "" }')
$S.Add('$existing = $existing -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""')
$S.Add('[IO.File]::WriteAllText($HOSTS, $existing.TrimEnd() + "`r`n" + ($block -join "`r`n"), [Text.Encoding]::UTF8)')
$S.Add('Log "Hosts written: $($HostLines.Count) entries"')
$S.Add('# 9. Firewall')
$S.Add('if (-not (Get-NetFirewallRule -DisplayName "XNET-Telegram" -ErrorAction SilentlyContinue)) {')
$S.Add('    New-NetFirewallRule -DisplayName "XNET-Telegram"   -Direction Outbound -Action Block -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null')
$S.Add('    New-NetFirewallRule -DisplayName "XNET-VPN-UDP"    -Direction Outbound -Action Block -Protocol UDP -RemotePort @(1194,51820) -Profile Any -ErrorAction SilentlyContinue | Out-Null')
$S.Add('    New-NetFirewallRule -DisplayName "XNET-Block-QUIC" -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Profile Any -ErrorAction SilentlyContinue | Out-Null')
$S.Add('    Log "Firewall rules added"')
$S.Add('}')
$S.Add('ipconfig /flushdns | Out-Null')
$S.Add('# 10. Status')
$S.Add('@{ installed=$true; paused=$false; base_sites_enabled=$P.base_sites_enabled; google_search_enabled=$P.google_search_enabled; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail; allowed=$ok; version="11.3" } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')
$S.Add('Log "=== Sync done: $ok domains ==="')
$S.Add('$logContent = Get-Content $LOG -ErrorAction SilentlyContinue')
$S.Add('if ($logContent -and $logContent.Count -gt 300) { $logContent[-300..-1] | Out-File $LOG -Encoding UTF8 -Force }')

try {
    [IO.File]::WriteAllLines("$DIR\sync.ps1", $S, [Text.Encoding]::UTF8)
    Write-Host "[+] sync.ps1 written ($($S.Count) lines)." -ForegroundColor Green
} catch {
    Write-Host "FATAL: Cannot write sync.ps1: $_" -ForegroundColor Red
    Read-Host; exit
}

# ==================================================
# tray.ps1
# ==================================================
Write-Host "Writing tray.ps1..." -ForegroundColor Yellow
$T = [System.Collections.Generic.List[string]]::new()
$T.Add('$mutex = New-Object System.Threading.Mutex($false, "Global\XNET_TRAY_MUTEX")')
$T.Add('if (-not $mutex.WaitOne(0, $false)) { exit }')
$T.Add('Add-Type -AssemblyName System.Windows.Forms')
$T.Add('Add-Type -AssemblyName System.Drawing')
$T.Add('$notify = New-Object System.Windows.Forms.NotifyIcon')
$T.Add('$notify.Icon = [System.Drawing.SystemIcons]::Shield')
$T.Add('$notify.Visible = $true')
$T.Add('$notify.Text = "X-NET Active"')
$T.Add('function Run-Sync {')
$T.Add('    if (Test-Path "C:\XNET\sync.ps1") {')
$T.Add('        Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\XNET\sync.ps1`"" -Verb RunAs -ErrorAction SilentlyContinue')
$T.Add('    }')
$T.Add('}')
$T.Add('function Update-Tray {')
$T.Add('    $f = "C:\XNET\status.json"')
$T.Add('    if (Test-Path $f) {')
$T.Add('        try {')
$T.Add('            $s = Get-Content $f -Raw | ConvertFrom-Json')
$T.Add('            if ($s.paused) { $notify.Icon = [System.Drawing.SystemIcons]::Warning; $t = "X-NET Paused" }')
$T.Add('            else { $notify.Icon = [System.Drawing.SystemIcons]::Shield; $t = "X-NET | " + $s.allowed + " domains | " + $s.last_updated }')
$T.Add('            if ($t.Length -gt 63) { $t = $t.Substring(0,60) + "..." }')
$T.Add('            $notify.Text = $t')
$T.Add('        } catch { $notify.Text = "X-NET Active" }')
$T.Add('    }')
$T.Add('}')
$T.Add('$menu = New-Object System.Windows.Forms.ContextMenu')
$T.Add('$r1 = New-Object System.Windows.Forms.MenuItem "Refresh Now"')
$T.Add('$r1.add_Click({ $notify.Text = "Syncing..."; Run-Sync; Start-Sleep 15; Update-Tray })')
$T.Add('$r2 = New-Object System.Windows.Forms.MenuItem "View Log"')
$T.Add('$r2.add_Click({ if (Test-Path "C:\XNET\sync_log.txt") { Start-Process notepad "C:\XNET\sync_log.txt" } })')
$T.Add('$r3 = New-Object System.Windows.Forms.MenuItem "Open Dashboard"')
$T.Add('$r3.add_Click({ $e = ""; if (Test-Path "C:\XNET\user.txt") { $e = (Get-Content "C:\XNET\user.txt" -First 1).Trim() }; Start-Process "https://meny0583285502.github.io/X-NET/?user=$e" })')
$T.Add('$r4 = New-Object System.Windows.Forms.MenuItem "Exit Tray"')
$T.Add('$r4.add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() })')
$T.Add('$menu.MenuItems.Add($r1) | Out-Null; $menu.MenuItems.Add($r2) | Out-Null; $menu.MenuItems.Add($r3) | Out-Null; $menu.MenuItems.Add("-") | Out-Null; $menu.MenuItems.Add($r4) | Out-Null')
$T.Add('$notify.ContextMenu = $menu')
$T.Add('$notify.add_DoubleClick({ $e = ""; if (Test-Path "C:\XNET\user.txt") { $e = (Get-Content "C:\XNET\user.txt" -First 1).Trim() }; Start-Process "https://meny0583285502.github.io/X-NET/?user=$e" })')
$T.Add('$timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 30000')
$T.Add('$timer.add_Tick({ Update-Tray }); $timer.Start(); Update-Tray')
$T.Add('$form = New-Object System.Windows.Forms.Form; $form.ShowInTaskbar = $false; $form.WindowState = "Minimized"')
$T.Add('[System.Windows.Forms.Application]::Run($form)')

try {
    [IO.File]::WriteAllLines("$DIR\tray.ps1", $T, [Text.Encoding]::UTF8)
    Write-Host "[+] tray.ps1 written." -ForegroundColor Green
} catch {
    Write-Host "FATAL: Cannot write tray.ps1: $_" -ForegroundColor Red
    Read-Host; exit
}

# Startup shortcut
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$sc.TargetPath = "powershell.exe"
$sc.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$sc.Save()

# Kill old tray + start new
Get-WmiObject Win32_Process -Filter "name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "tray\.ps1" } |
    ForEach-Object { $_.Terminate() | Out-Null }
Start-Sleep 1
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`"" -ErrorAction SilentlyContinue
Write-Host "[+] Tray started." -ForegroundColor Green

# Scheduled Task
schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
schtasks /create /tn "XNET_Sync" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\sync.ps1`"" /sc minute /mo 1 /ru "SYSTEM" /f | Out-Null
Write-Host "[+] Scheduled Task created." -ForegroundColor Green

# Run sync now
Write-Host "[+] Running sync now..." -ForegroundColor Yellow
& "$DIR\sync.ps1"

# Show results
Write-Host ""
Write-Host "=== C:\XNET contents ===" -ForegroundColor Cyan
Get-ChildItem $DIR -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name) ($($_.Length) bytes)" }
Write-Host ""
Write-Host "=== sync_log.txt ===" -ForegroundColor Cyan
$logFile = "$DIR\sync_log.txt"
if (Test-Path $logFile) {
    Get-Content $logFile | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
} else {
    Write-Host "  (no log created)" -ForegroundColor Red
}
Write-Host "====================" -ForegroundColor Cyan
Read-Host "Press Enter to exit"
