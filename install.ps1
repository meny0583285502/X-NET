# X-NET v11.2 - install.ps1
param([string]$UserEmail = "", [switch]$Silent)

$VERSION = "11.2"
$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"

if (-not (Test-Path $DIR)) { New-Item $DIR -ItemType Directory -Force | Out-Null }

$EmailFile = "$DIR\user.txt"
if ($UserEmail)               { $UserEmail | Out-File $EmailFile -Encoding UTF8 -Force }
elseif (Test-Path $EmailFile) { $UserEmail = (Get-Content $EmailFile -First 1).Trim() }
else { if (-not $Silent) { Write-Host "ERROR: No email"; Read-Host }; exit }

if (-not $Silent) { Write-Host "===== X-NET v$VERSION | $UserEmail =====" -ForegroundColor Cyan }

# ==================================================
# שלב 1 - כתיבת sync.ps1 שורה-שורה
# ==================================================
$S = [System.Collections.Generic.List[string]]::new()

$S.Add('$DIR    = "C:\XNET"')
$S.Add('$LOG    = "$DIR\sync_log.txt"')
$S.Add('$HOSTS  = "$env:SystemRoot\System32\drivers\etc\hosts"')
$S.Add('$GH_RAW = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"')
$S.Add('function Log($msg) { "$(Get-Date -Format ''HH:mm:ss'') $msg" | Out-File $LOG -Append -Encoding UTF8 }')
$S.Add('')
$S.Add('if (-not (Test-Path "$DIR\user.txt")) { Log "ERROR: user.txt missing"; exit }')
$S.Add('$UserEmail = (Get-Content "$DIR\user.txt" -First 1).Trim()')
$S.Add('$Safe = $UserEmail -replace "@","_at_" -replace "\.","_dot_"')
$S.Add('Log "--- Sync start | $UserEmail ---"')
$S.Add('')
$S.Add('# 1. Release DNS')
$S.Add('Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {')
$S.Add('    Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue')
$S.Add('}')
$S.Add('ipconfig /flushdns | Out-Null')
$S.Add('Start-Sleep -Seconds 2')
$S.Add('Log "DNS released"')
$S.Add('')
$S.Add('# 2. Fetch profile')
$S.Add('try {')
$S.Add('    $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop')
$S.Add('    Log "Profile fetched OK"')
$S.Add('} catch {')
$S.Add('    Log "ERROR fetching profile: $_"')
$S.Add('    exit')
$S.Add('}')
$S.Add('')
$S.Add('# 3. Uninstall?')
$S.Add('if ($P.requests.uninstall_approved -eq $true) {')
$S.Add('    Log "Uninstall approved - removing..."')
$S.Add('    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null')
$S.Add('    Get-WmiObject Win32_Process -Filter "name=''powershell.exe''" | Where-Object { $_.CommandLine -match "tray\.ps1" } | ForEach-Object { $_.Terminate() }')
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
$S.Add('')
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
$S.Add('')
$S.Add('# 5. Build allowed list')
$S.Add('$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)')
$S.Add('$sys = "googleapis.com","gstatic.com","accounts.google.com","googleusercontent.com","meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com","api.emailjs.com","update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com","ctldl.windowsupdate.com","wustat.windows.com","dns.msftncsi.com","login.microsoftonline.com","login.live.com","microsoft.com","office.com","ocsp.digicert.com","ocsp.pki.goog","crl.microsoft.com","pki.goog"')
$S.Add('$sys | ForEach-Object { [void]$Allowed.Add($_) }')
$S.Add('')
$S.Add('if ($P.base_sites_enabled -eq $true) {')
$S.Add('    try {')
$S.Add('        $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop')
$S.Add('        $Base.allowed_domains | ForEach-Object { $d = ($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }')
$S.Add('        Log "Base whitelist loaded: $($Base.allowed_domains.Count) domains"')
$S.Add('    } catch { Log "Base whitelist error: $_" }')
$S.Add('}')
$S.Add('if ($P.google_search_enabled -eq $true) { [void]$Allowed.Add("google.com"); [void]$Allowed.Add("google.co.il"); Log "Google search: ON" }')
$S.Add('if ($P.allowed_domains -and $P.allowed_domains.Count -gt 0) {')
$S.Add('    $P.allowed_domains | ForEach-Object { $d = ($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }')
$S.Add('    Log "Personal domains: $($P.allowed_domains.Count)"')
$S.Add('}')
$S.Add('Log "Total allowed domains: $($Allowed.Count)"')
$S.Add('')
$S.Add('# 6. Save whitelist.txt + Resolve (DNS still open!)')
$S.Add('$AllowedList = $Allowed | Sort-Object')
$S.Add('$AllowedList | Out-File "$DIR\whitelist.txt" -Encoding UTF8 -Force')
$S.Add('')
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
$S.Add('Log "Resolved $ok domains -> $($HostLines.Count) host entries"')
$S.Add('')
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
$S.Add('Log "DNS locked to 127.0.0.1"')
$S.Add('')
$S.Add('# 8. Write hosts file')
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
$S.Add('$existing = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue')
$S.Add('if (-not $existing) { $existing = "" }')
$S.Add('$existing = $existing -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""')
$S.Add('[IO.File]::WriteAllText($HOSTS, $existing.TrimEnd() + "`r`n" + ($block -join "`r`n"), [Text.Encoding]::UTF8)')
$S.Add('Log "Hosts file written"')
$S.Add('')
$S.Add('# 9. Firewall (only if missing)')
$S.Add('if (-not (Get-NetFirewallRule -DisplayName "XNET-Telegram" -ErrorAction SilentlyContinue)) {')
$S.Add('    New-NetFirewallRule -DisplayName "XNET-Telegram"   -Direction Outbound -Action Block -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null')
$S.Add('    New-NetFirewallRule -DisplayName "XNET-VPN-UDP"    -Direction Outbound -Action Block -Protocol UDP -RemotePort @(1194,51820) -Profile Any -ErrorAction SilentlyContinue | Out-Null')
$S.Add('    New-NetFirewallRule -DisplayName "XNET-Block-QUIC" -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Profile Any -ErrorAction SilentlyContinue | Out-Null')
$S.Add('    Log "Firewall rules added"')
$S.Add('}')
$S.Add('ipconfig /flushdns | Out-Null')
$S.Add('')
$S.Add('# 10. Save status.json')
$S.Add('@{ installed=$true; paused=$false; base_sites_enabled=$P.base_sites_enabled; google_search_enabled=$P.google_search_enabled; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail; allowed=$ok; version="11.2" } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')
$S.Add('Log "--- Sync done | $ok domains ---"')
$S.Add('')
$S.Add('# Keep log max 200 lines')
$S.Add('$logContent = Get-Content $LOG -ErrorAction SilentlyContinue')
$S.Add('if ($logContent -and $logContent.Count -gt 200) { $logContent[-200..-1] | Out-File $LOG -Encoding UTF8 -Force }')

[IO.File]::WriteAllLines("$DIR\sync.ps1", $S, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] sync.ps1 written." -ForegroundColor Green }

# ==================================================
# שלב 2 - Tray icon
# ==================================================
$T = [System.Collections.Generic.List[string]]::new()
$T.Add('$mutex = New-Object System.Threading.Mutex($false, "Global\XNET_TRAY_MUTEX")')
$T.Add('if (-not $mutex.WaitOne(0, $false)) { exit }')
$T.Add('Add-Type -AssemblyName System.Windows.Forms')
$T.Add('Add-Type -AssemblyName System.Drawing')
$T.Add('$notify = New-Object System.Windows.Forms.NotifyIcon')
$T.Add('$notify.Icon = [System.Drawing.SystemIcons]::Shield')
$T.Add('$notify.Visible = $true')
$T.Add('$notify.Text = "X-NET Active"')
$T.Add('')
$T.Add('function Run-Sync {')
$T.Add('    if (Test-Path "C:\XNET\sync.ps1") {')
$T.Add('        Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\XNET\sync.ps1`"" -Verb RunAs -ErrorAction SilentlyContinue')
$T.Add('    }')
$T.Add('}')
$T.Add('')
$T.Add('function Update-Tray {')
$T.Add('    $f = "C:\XNET\status.json"')
$T.Add('    if (Test-Path $f) {')
$T.Add('        try {')
$T.Add('            $s = Get-Content $f -Raw | ConvertFrom-Json')
$T.Add('            if ($s.paused) {')
$T.Add('                $notify.Icon = [System.Drawing.SystemIcons]::Warning')
$T.Add('                $t = "X-NET Paused"')
$T.Add('            } else {')
$T.Add('                $notify.Icon = [System.Drawing.SystemIcons]::Shield')
$T.Add('                $t = "X-NET | " + $s.allowed + " domains | " + $s.last_updated')
$T.Add('            }')
$T.Add('            if ($t.Length -gt 63) { $t = $t.Substring(0,60) + "..." }')
$T.Add('            $notify.Text = $t')
$T.Add('        } catch { $notify.Text = "X-NET Active" }')
$T.Add('    }')
$T.Add('}')
$T.Add('')
$T.Add('$menu = New-Object System.Windows.Forms.ContextMenu')
$T.Add('$r1 = New-Object System.Windows.Forms.MenuItem "Refresh Now"')
$T.Add('$r1.add_Click({ $notify.Text = "X-NET Syncing..."; Run-Sync; Start-Sleep 15; Update-Tray })')
$T.Add('$r2 = New-Object System.Windows.Forms.MenuItem "View Log"')
$T.Add('$r2.add_Click({ if (Test-Path "C:\XNET\sync_log.txt") { Start-Process notepad "C:\XNET\sync_log.txt" } })')
$T.Add('$r3 = New-Object System.Windows.Forms.MenuItem "Open Dashboard"')
$T.Add('$r3.add_Click({ $e = ""; if (Test-Path "C:\XNET\user.txt") { $e = (Get-Content "C:\XNET\user.txt" -First 1).Trim() }; Start-Process "https://meny0583285502.github.io/X-NET/?user=$e" })')
$T.Add('$r4 = New-Object System.Windows.Forms.MenuItem "Exit Tray"')
$T.Add('$r4.add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() })')
$T.Add('$menu.MenuItems.Add($r1) | Out-Null')
$T.Add('$menu.MenuItems.Add($r2) | Out-Null')
$T.Add('$menu.MenuItems.Add($r3) | Out-Null')
$T.Add('$menu.MenuItems.Add("-") | Out-Null')
$T.Add('$menu.MenuItems.Add($r4) | Out-Null')
$T.Add('$notify.ContextMenu = $menu')
$T.Add('$notify.add_DoubleClick({ $e = ""; if (Test-Path "C:\XNET\user.txt") { $e = (Get-Content "C:\XNET\user.txt" -First 1).Trim() }; Start-Process "https://meny0583285502.github.io/X-NET/?user=$e" })')
$T.Add('$timer = New-Object System.Windows.Forms.Timer')
$T.Add('$timer.Interval = 30000')
$T.Add('$timer.add_Tick({ Update-Tray })')
$T.Add('$timer.Start()')
$T.Add('Update-Tray')
$T.Add('$form = New-Object System.Windows.Forms.Form')
$T.Add('$form.ShowInTaskbar = $false; $form.WindowState = "Minimized"')
$T.Add('[System.Windows.Forms.Application]::Run($form)')

[IO.File]::WriteAllLines("$DIR\tray.ps1", $T, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] tray.ps1 written." -ForegroundColor Green }

# Startup shortcut
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$sc.TargetPath = "powershell.exe"
$sc.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$sc.Save()

# Kill old tray + start new
Get-WmiObject Win32_Process -Filter "name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "tray\.ps1" } |
    ForEach-Object { $_.Terminate() }
Start-Sleep 1
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`"" -ErrorAction SilentlyContinue
if (-not $Silent) { Write-Host "[+] Tray started." -ForegroundColor Green }

# ==================================================
# שלב 3 - Scheduled Task כל דקה
# ==================================================
schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
schtasks /create /tn "XNET_Sync" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\sync.ps1`"" /sc minute /mo 1 /ru "SYSTEM" /f 2>&1 | Out-Null
if (-not $Silent) { Write-Host "[+] Scheduled Task: every 1 minute." -ForegroundColor Green }

# ==================================================
# שלב 4 - הרץ sync עכשיו
# ==================================================
if (-not $Silent) { Write-Host "[+] Running first sync now..." -ForegroundColor Yellow }
& "$DIR\sync.ps1"

if (-not $Silent) {
    Write-Host "[+] Done! X-NET v$VERSION active." -ForegroundColor Green
    Write-Host "[i] Check C:\XNET\sync_log.txt for details." -ForegroundColor Cyan
    Start-Process "https://meny0583285502.github.io/X-NET/?user=$UserEmail&installed=1"
    Start-Sleep 1
}
# DEBUG - הצג לוג ותוכן תיקיה
if (-not $Silent) {
    Write-Host ""
    Write-Host "=== C:\XNET contents ===" -ForegroundColor Cyan
    if (Test-Path $DIR) {
        Get-ChildItem $DIR | ForEach-Object { Write-Host "  $($_.Name) ($($_.Length) bytes)" }
    } else {
        Write-Host "  (directory does not exist!)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "=== sync_log.txt ===" -ForegroundColor Cyan
    $logFile = "$DIR\sync_log.txt"
    if (Test-Path $logFile) {
        Get-Content $logFile | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    } else {
        Write-Host "  (log not created - sync crashed before first log line)" -ForegroundColor Red
        Write-Host "  Check: is C:\XNET\sync.ps1 present?" -ForegroundColor Red
    }
    Write-Host "====================" -ForegroundColor Cyan
    Read-Host "Press Enter to exit"
}
