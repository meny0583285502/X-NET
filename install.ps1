# X-NET v11.1 - install.ps1
param([string]$UserEmail = "", [switch]$Silent)

$VERSION = "11.1"
$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"

if (-not (Test-Path $DIR)) { New-Item $DIR -ItemType Directory -Force | Out-Null }

$EmailFile = "$DIR\user.txt"
if ($UserEmail)             { $UserEmail | Out-File $EmailFile -Encoding UTF8 -Force }
elseif (Test-Path $EmailFile) { $UserEmail = (Get-Content $EmailFile -First 1).Trim() }
else { if (-not $Silent) { Write-Host "ERROR: No email"; Read-Host }; exit }

if (-not $Silent) { Write-Host "===== X-NET v$VERSION | $UserEmail =====" -ForegroundColor Cyan }

# ==================================================
# שלב 1 - כתיבת sync.ps1 שורה-שורה (בלי here-string)
# sync.ps1 הוא זה שרץ כל דקה ועושה את כל העבודה
# ==================================================
$syncLines = [System.Collections.Generic.List[string]]::new()
$syncLines.Add('# X-NET sync.ps1 - runs every minute as SYSTEM')
$syncLines.Add('$DIR    = "C:\XNET"')
$syncLines.Add('$HOSTS  = "$env:SystemRoot\System32\drivers\etc\hosts"')
$syncLines.Add('$GH_RAW = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"')
$syncLines.Add('')
$syncLines.Add('$EmailFile = "$DIR\user.txt"')
$syncLines.Add('if (-not (Test-Path $EmailFile)) { exit }')
$syncLines.Add('$UserEmail = (Get-Content $EmailFile -First 1).Trim()')
$syncLines.Add('$Safe = $UserEmail -replace "@","_at_" -replace "\.","_dot_"')
$syncLines.Add('')
$syncLines.Add('# STEP 1: Release DNS so we can reach the internet')
$syncLines.Add('Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {')
$syncLines.Add('    Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue')
$syncLines.Add('}')
$syncLines.Add('ipconfig /flushdns | Out-Null')
$syncLines.Add('Start-Sleep -Seconds 2')
$syncLines.Add('')
$syncLines.Add('# STEP 2: Fetch profile from GitHub')
$syncLines.Add('try {')
$syncLines.Add('    $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop')
$syncLines.Add('} catch {')
$syncLines.Add('    exit  # leave DNS open, retry next minute')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('# STEP 3: Uninstall')
$syncLines.Add('if ($P.requests.uninstall_approved -eq $true) {')
$syncLines.Add('    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null')
$syncLines.Add('    Get-WmiObject Win32_Process -Filter "name=''powershell.exe''" | Where-Object { $_.CommandLine -match "tray\.ps1" } | ForEach-Object { $_.Terminate() }')
$syncLines.Add('    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue }')
$syncLines.Add('    attrib -r $HOSTS 2>$null')
$syncLines.Add('    $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue')
$syncLines.Add('    if ($h) { [IO.File]::WriteAllText($HOSTS, ($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""), [Text.Encoding]::UTF8) }')
$syncLines.Add('    foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox")) {')
$syncLines.Add('        Remove-ItemProperty $k -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -ErrorAction SilentlyContinue')
$syncLines.Add('    }')
$syncLines.Add('    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue')
$syncLines.Add('    ipconfig /flushdns | Out-Null')
$syncLines.Add('    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk" -Force -ErrorAction SilentlyContinue')
$syncLines.Add('    Start-Sleep 1')
$syncLines.Add('    Remove-Item $DIR -Recurse -Force -ErrorAction SilentlyContinue')
$syncLines.Add('    exit')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('# STEP 4: Pause')
$syncLines.Add('if ($P.requests.pause -and $P.requests.pause.until) {')
$syncLines.Add('    try {')
$syncLines.Add('        $until = [datetime]::Parse($P.requests.pause.until).ToUniversalTime()')
$syncLines.Add('        if ((Get-Date).ToUniversalTime() -lt $until) {')
$syncLines.Add('            attrib -r $HOSTS 2>$null')
$syncLines.Add('            $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue')
$syncLines.Add('            if ($h) { [IO.File]::WriteAllText($HOSTS, ($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""), [Text.Encoding]::UTF8) }')
$syncLines.Add('            ipconfig /flushdns | Out-Null')
$syncLines.Add('            @{ paused=$true; paused_until=$P.requests.pause.until; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')
$syncLines.Add('            exit')
$syncLines.Add('        }')
$syncLines.Add('    } catch {}')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('# STEP 5: Build allowed domains list')
$syncLines.Add('$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)')
$syncLines.Add('$systemDomains = @("googleapis.com","gstatic.com","accounts.google.com","googleusercontent.com","meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com","api.emailjs.com","update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com","ctldl.windowsupdate.com","wustat.windows.com","dns.msftncsi.com","login.microsoftonline.com","login.live.com","microsoft.com","office.com","ocsp.digicert.com","ocsp.pki.goog","crl.microsoft.com","pki.goog")')
$syncLines.Add('$systemDomains | ForEach-Object { [void]$Allowed.Add($_) }')
$syncLines.Add('')
$syncLines.Add('if ($P.base_sites_enabled -eq $true) {')
$syncLines.Add('    try {')
$syncLines.Add('        $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop')
$syncLines.Add('        $Base.allowed_domains | ForEach-Object { $d = ($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }')
$syncLines.Add('    } catch {}')
$syncLines.Add('}')
$syncLines.Add('if ($P.google_search_enabled -eq $true) { [void]$Allowed.Add("google.com"); [void]$Allowed.Add("google.co.il") }')
$syncLines.Add('if ($P.allowed_domains) {')
$syncLines.Add('    $P.allowed_domains | ForEach-Object { $d = ($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('# STEP 6: Save whitelist.txt (DNS still open here!)')
$syncLines.Add('$AllowedList = $Allowed | Sort-Object')
$syncLines.Add('$AllowedList | Out-File "$DIR\whitelist.txt" -Encoding UTF8 -Force')
$syncLines.Add('')
$syncLines.Add('# STEP 7: Resolve IPs (DNS still open!)')
$syncLines.Add('Start-Sleep -Seconds 1')
$syncLines.Add('$HostLines = [System.Collections.Generic.List[string]]::new()')
$syncLines.Add('$ok = 0')
$syncLines.Add('foreach ($root in $AllowedList) {')
$syncLines.Add('    $variants = @($root); if (-not $root.StartsWith("www.")) { $variants += "www.$root" }')
$syncLines.Add('    foreach ($v in $variants) {')
$syncLines.Add('        try {')
$syncLines.Add('            $ips = [Net.Dns]::GetHostAddresses($v) | Where-Object { $_.AddressFamily -eq "InterNetwork" }')
$syncLines.Add('            foreach ($ip in $ips) { $HostLines.Add("$($ip.IPAddressToString)`t$v") }')
$syncLines.Add('            $ok++')
$syncLines.Add('        } catch {}')
$syncLines.Add('    }')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('# STEP 8: Lock DNS to 127.0.0.1')
$syncLines.Add('Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {')
$syncLines.Add('    try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue } catch {}')
$syncLines.Add('}')
$syncLines.Add('Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled } | ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue }')
$syncLines.Add('')
$syncLines.Add('# Block DoH in browsers')
$syncLines.Add('foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {')
$syncLines.Add('    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }')
$syncLines.Add('    Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force')
$syncLines.Add('    Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force')
$syncLines.Add('}')
$syncLines.Add('$k = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"')
$syncLines.Add('if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }')
$syncLines.Add('Set-ItemProperty $k "DNSOverHTTPS" "{\"Enabled\": false}" -Force')
$syncLines.Add('')
$syncLines.Add('# STEP 9: Write hosts file')
$syncLines.Add('attrib -r $HOSTS 2>$null')
$syncLines.Add('$block = [System.Collections.Generic.List[string]]::new()')
$syncLines.Add('$block.Add("# [XNET] DO NOT EDIT")')
$syncLines.Add('$block.Add("# Updated: $(Get-Date -Format ''yyyy-MM-dd HH:mm:ss'') | Domains: $ok")')
$syncLines.Add('$block.Add("127.0.0.1 localhost")')
$syncLines.Add('$block.Add("::1 localhost")')
$syncLines.Add('$block.Add("")')
$syncLines.Add('foreach ($line in $HostLines) { $block.Add($line) }')
$syncLines.Add('$block.Add("")')
$syncLines.Add('$block.Add("# [/XNET]")')
$syncLines.Add('$existing = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue; if (-not $existing) { $existing = "" }')
$syncLines.Add('$existing = $existing -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""')
$syncLines.Add('[IO.File]::WriteAllText($HOSTS, $existing.TrimEnd() + "`r`n" + ($block -join "`r`n"), [Text.Encoding]::UTF8)')
$syncLines.Add('')
$syncLines.Add('# Firewall rules (only if missing)')
$syncLines.Add('if (-not (Get-NetFirewallRule -DisplayName "XNET-Telegram" -ErrorAction SilentlyContinue)) {')
$syncLines.Add('    New-NetFirewallRule -DisplayName "XNET-Telegram"   -Direction Outbound -Action Block -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null')
$syncLines.Add('    New-NetFirewallRule -DisplayName "XNET-VPN-UDP"    -Direction Outbound -Action Block -Protocol UDP -RemotePort @(1194,51820) -Profile Any -ErrorAction SilentlyContinue | Out-Null')
$syncLines.Add('    New-NetFirewallRule -DisplayName "XNET-Block-QUIC" -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Profile Any -ErrorAction SilentlyContinue | Out-Null')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('ipconfig /flushdns | Out-Null')
$syncLines.Add('')
$syncLines.Add('# STEP 10: Save status.json')
$syncLines.Add('@{ installed=$true; paused=$false; base_sites_enabled=$P.base_sites_enabled; google_search_enabled=$P.google_search_enabled; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail; allowed=$ok; version="11.1" } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')

[IO.File]::WriteAllLines("$DIR\sync.ps1", $syncLines, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] sync.ps1 written ($($syncLines.Count) lines)." -ForegroundColor Green }

# ==================================================
# שלב 2 - Tray icon
# ==================================================
$trayLines = [System.Collections.Generic.List[string]]::new()
$trayLines.Add('$mutex = New-Object System.Threading.Mutex($false, "Global\XNET_TRAY_MUTEX")')
$trayLines.Add('if (-not $mutex.WaitOne(0, $false)) { exit }')
$trayLines.Add('Add-Type -AssemblyName System.Windows.Forms')
$trayLines.Add('Add-Type -AssemblyName System.Drawing')
$trayLines.Add('$notify = New-Object System.Windows.Forms.NotifyIcon')
$trayLines.Add('$notify.Icon = [System.Drawing.SystemIcons]::Shield')
$trayLines.Add('$notify.Visible = $true')
$trayLines.Add('$notify.Text = "X-NET - Loading..."')
$trayLines.Add('')
$trayLines.Add('function Run-Sync {')
$trayLines.Add('    if (Test-Path "C:\XNET\sync.ps1") {')
$trayLines.Add('        Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\XNET\sync.ps1`"" -Verb RunAs -ErrorAction SilentlyContinue')
$trayLines.Add('    }')
$trayLines.Add('}')
$trayLines.Add('')
$trayLines.Add('function Update-Tray {')
$trayLines.Add('    $f = "C:\XNET\status.json"')
$trayLines.Add('    if (Test-Path $f) {')
$trayLines.Add('        try {')
$trayLines.Add('            $s = Get-Content $f -Raw | ConvertFrom-Json')
$trayLines.Add('            if ($s.paused) {')
$trayLines.Add('                $notify.Icon = [System.Drawing.SystemIcons]::Warning')
$trayLines.Add('                $t = "X-NET - Paused"')
$trayLines.Add('            } else {')
$trayLines.Add('                $notify.Icon = [System.Drawing.SystemIcons]::Shield')
$trayLines.Add('                $t = "X-NET | " + $s.allowed + " domains | " + $s.last_updated')
$trayLines.Add('            }')
$trayLines.Add('            if ($t.Length -gt 63) { $t = $t.Substring(0,60) + "..." }')
$trayLines.Add('            $notify.Text = $t')
$trayLines.Add('        } catch { $notify.Text = "X-NET Active" }')
$trayLines.Add('    }')
$trayLines.Add('}')
$trayLines.Add('')
$trayLines.Add('$menu = New-Object System.Windows.Forms.ContextMenu')
$trayLines.Add('$r1 = New-Object System.Windows.Forms.MenuItem "Refresh Now"')
$trayLines.Add('$r1.add_Click({ $notify.Text = "X-NET - Syncing..."; Run-Sync; Start-Sleep 12; Update-Tray })')
$trayLines.Add('$r2 = New-Object System.Windows.Forms.MenuItem "Open Dashboard"')
$trayLines.Add('$r2.add_Click({ $e = ""; if (Test-Path "C:\XNET\user.txt") { $e = (Get-Content "C:\XNET\user.txt" -First 1).Trim() }; Start-Process "https://meny0583285502.github.io/X-NET/?user=$e" })')
$trayLines.Add('$r3 = New-Object System.Windows.Forms.MenuItem "Exit Tray"')
$trayLines.Add('$r3.add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() })')
$trayLines.Add('$menu.MenuItems.Add($r1) | Out-Null')
$trayLines.Add('$menu.MenuItems.Add($r2) | Out-Null')
$trayLines.Add('$menu.MenuItems.Add("-") | Out-Null')
$trayLines.Add('$menu.MenuItems.Add($r3) | Out-Null')
$trayLines.Add('$notify.ContextMenu = $menu')
$trayLines.Add('$notify.add_DoubleClick({ $e = ""; if (Test-Path "C:\XNET\user.txt") { $e = (Get-Content "C:\XNET\user.txt" -First 1).Trim() }; Start-Process "https://meny0583285502.github.io/X-NET/?user=$e" })')
$trayLines.Add('$timer = New-Object System.Windows.Forms.Timer')
$trayLines.Add('$timer.Interval = 30000')
$trayLines.Add('$timer.add_Tick({ Update-Tray })')
$trayLines.Add('$timer.Start()')
$trayLines.Add('Update-Tray')
$trayLines.Add('$form = New-Object System.Windows.Forms.Form')
$trayLines.Add('$form.ShowInTaskbar = $false')
$trayLines.Add('$form.WindowState = "Minimized"')
$trayLines.Add('[System.Windows.Forms.Application]::Run($form)')

[IO.File]::WriteAllLines("$DIR\tray.ps1", $trayLines, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] tray.ps1 written." -ForegroundColor Green }

# Startup shortcut
$WshShell = New-Object -ComObject WScript.Shell
$sc = $WshShell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$sc.TargetPath = "powershell.exe"
$sc.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$sc.Save()

# Kill old tray, start new
Get-WmiObject Win32_Process -Filter "name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "tray\.ps1" } |
    ForEach-Object { $_.Terminate() }
Start-Sleep 1
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`"" -ErrorAction SilentlyContinue
if (-not $Silent) { Write-Host "[+] Tray started." -ForegroundColor Green }

# ==================================================
# שלב 3 - Scheduled Task (כל דקה, תמיד מחדש)
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
    Start-Process "https://meny0583285502.github.io/X-NET/?user=$UserEmail&installed=1"
    Start-Sleep 1
}
