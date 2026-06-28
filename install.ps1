# X-NET v12.0 - install.ps1
param([string]$UserEmail = "", [switch]$Silent)
$VERSION = "12.0"
$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"

# Self-elevation - מעביר את UserEmail לתהליך הAdmin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    if ($UserEmail) { $argList += " -UserEmail `"$UserEmail`"" }
    Start-Process powershell -ArgumentList $argList -Verb RunAs
    exit
}

# צור תיקיה
if (-not (Test-Path $DIR)) { New-Item -Path $DIR -ItemType Directory -Force | Out-Null }

# אימייל
$EmailFile = "$DIR\user.txt"
if ($UserEmail)               { $UserEmail | Out-File $EmailFile -Encoding UTF8 -Force }
elseif (Test-Path $EmailFile) { $UserEmail = (Get-Content $EmailFile -First 1).Trim() }
else {
    $UserEmail = Read-Host "Enter email"
    $UserEmail | Out-File $EmailFile -Encoding UTF8 -Force
}
Write-Host "X-NET v$VERSION | $UserEmail" -ForegroundColor Cyan

# כתוב sync.ps1
$utf8 = New-Object System.Text.UTF8Encoding($false)
$S = [System.Collections.Generic.List[string]]::new()
$S.Add('$DIR    = "C:\XNET"')
$S.Add('$LOG    = "$DIR\sync_log.txt"')
$S.Add('$HOSTS  = "$env:SystemRoot\System32\drivers\etc\hosts"')
$S.Add('$GH_RAW = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"')
$S.Add('function Log($m) { "$(Get-Date -Format ''HH:mm:ss'') $m" | Out-File $LOG -Append -Encoding UTF8 }')
$S.Add('if (-not (Test-Path "$DIR\user.txt")) { exit }')
$S.Add('$UserEmail = (Get-Content "$DIR\user.txt" -First 1).Trim()')
$S.Add('$Safe = $UserEmail -replace "@","_at_" -replace "\.","_dot_"')
$S.Add('Log "=== START $UserEmail ==="')
$S.Add('# שחרר DNS')
$S.Add('Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue }')
$S.Add('ipconfig /flushdns | Out-Null')
$S.Add('Start-Sleep -Seconds 2')
$S.Add('Log "DNS released"')
$S.Add('# שלוף פרופיל')
$S.Add('try { $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop; Log "Profile OK" }')
$S.Add('catch { Log "Profile FAIL: $_"; exit }')
$S.Add('# הסרה?')
$S.Add('if ($P.requests.uninstall_approved -eq $true) {')
$S.Add('    Log "Uninstall..."')
$S.Add('    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null')
$S.Add('    Get-WmiObject Win32_Process -Filter "name=''powershell.exe''" | Where-Object { $_.CommandLine -match "tray" } | ForEach-Object { $_.Terminate() | Out-Null }')
$S.Add('    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue }')
$S.Add('    attrib -r $HOSTS 2>$null')
$S.Add('    $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue')
$S.Add('    if ($h) { [IO.File]::WriteAllText($HOSTS,($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""),[Text.Encoding]::UTF8) }')
$S.Add('    foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox")) { Remove-ItemProperty $k -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -ErrorAction SilentlyContinue }')
$S.Add('    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue')
$S.Add('    ipconfig /flushdns | Out-Null')
$S.Add('    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk" -Force -ErrorAction SilentlyContinue')
$S.Add('    Start-Sleep 1; Remove-Item $DIR -Recurse -Force -ErrorAction SilentlyContinue; exit')
$S.Add('}')
$S.Add('# השהיה?')
$S.Add('if ($P.requests.pause -and $P.requests.pause.until) {')
$S.Add('    try {')
$S.Add('        if ((Get-Date).ToUniversalTime() -lt [datetime]::Parse($P.requests.pause.until).ToUniversalTime()) {')
$S.Add('            Log "PAUSED"')
$S.Add('            attrib -r $HOSTS 2>$null')
$S.Add('            $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue')
$S.Add('            if ($h) { [IO.File]::WriteAllText($HOSTS,($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""),[Text.Encoding]::UTF8) }')
$S.Add('            ipconfig /flushdns | Out-Null')
$S.Add('            @{paused=$true;paused_until=$P.requests.pause.until;last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss");user=$UserEmail} | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')
$S.Add('            exit')
$S.Add('        }')
$S.Add('    } catch { Log "Pause err: $_" }')
$S.Add('}')
$S.Add('# בנה רשימה')
$S.Add('$A = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)')
$S.Add('"googleapis.com","gstatic.com","accounts.google.com","googleusercontent.com","meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com","api.emailjs.com","update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com","ctldl.windowsupdate.com","wustat.windows.com","dns.msftncsi.com","login.microsoftonline.com","login.live.com","microsoft.com","office.com","ocsp.digicert.com","ocsp.pki.goog","crl.microsoft.com","pki.goog" -split "," | ForEach-Object { [void]$A.Add($_) }')
$S.Add('if ($P.base_sites_enabled -eq $true) { try { $B=Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop; $B.allowed_domains|ForEach-Object{$d=($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.","";[void]$A.Add($d)}; Log "Base: $($B.allowed_domains.Count)" } catch { Log "Base err: $_" } }')
$S.Add('if ($P.google_search_enabled -eq $true) { [void]$A.Add("google.com"); [void]$A.Add("google.co.il"); Log "Google: ON" }')
$S.Add('if ($P.allowed_domains -and $P.allowed_domains.Count -gt 0) { $P.allowed_domains|ForEach-Object{$d=($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.","";[void]$A.Add($d)}; Log "Personal: $($P.allowed_domains.Count)" }')
$S.Add('Log "Total: $($A.Count)"')
$S.Add('# שמור whitelist + Resolve (DNS פתוח!)')
$S.Add('$AL = $A | Sort-Object')
$S.Add('$AL | Out-File "$DIR\whitelist.txt" -Encoding UTF8 -Force')
$S.Add('$H = [System.Collections.Generic.List[string]]::new()')
$S.Add('$ok = 0')
$S.Add('foreach ($root in $AL) {')
$S.Add('    $vv = @($root); if (-not $root.StartsWith("www.")) { $vv += "www.$root" }')
$S.Add('    foreach ($v in $vv) { try { $ips=[Net.Dns]::GetHostAddresses($v)|Where-Object{$_.AddressFamily -eq "InterNetwork"}; foreach($ip in $ips){$H.Add("$($ip.IPAddressToString)`t$v")}; $ok++ } catch {} }')
$S.Add('}')
$S.Add('Log "Resolved: $ok -> $($H.Count) entries"')
$S.Add('# נעל DNS')
$S.Add('Get-NetAdapter|Where-Object Status -eq Up|ForEach-Object{ try{Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue}catch{} }')
$S.Add('Get-NetAdapterBinding|Where-Object{$_.ComponentID -eq "ms_tcpip6" -and $_.Enabled}|ForEach-Object{Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue}')
$S.Add('foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge")) { if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}; Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force; Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force }')
$S.Add('$k="HKLM:\SOFTWARE\Policies\Mozilla\Firefox"; if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}; Set-ItemProperty $k "DNSOverHTTPS" "{""Enabled"": false}" -Force')
$S.Add('Log "DNS locked"')
$S.Add('# כתוב hosts')
$S.Add('attrib -r $HOSTS 2>$null')
$S.Add('$bl=[System.Collections.Generic.List[string]]::new()')
$S.Add('$bl.Add("# [XNET] DO NOT EDIT")')
$S.Add('$bl.Add("# $(Get-Date -Format ''yyyy-MM-dd HH:mm:ss'') | $ok domains")')
$S.Add('$bl.Add("127.0.0.1 localhost"); $bl.Add("::1 localhost"); $bl.Add("")')
$S.Add('foreach ($line in $H) { $bl.Add($line) }')
$S.Add('$bl.Add(""); $bl.Add("# [/XNET]")')
$S.Add('$ex=Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue; if(-not $ex){$ex=""}')
$S.Add('$ex=$ex -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""')
$S.Add('[IO.File]::WriteAllText($HOSTS,$ex.TrimEnd()+"`r`n"+($bl -join "`r`n"),[Text.Encoding]::UTF8)')
$S.Add('Log "Hosts written: $($H.Count)"')
$S.Add('# Firewall')
$S.Add('if(-not(Get-NetFirewallRule -DisplayName "XNET-Telegram" -ErrorAction SilentlyContinue)){')
$S.Add('    New-NetFirewallRule -DisplayName "XNET-Telegram" -Direction Outbound -Action Block -RemoteAddress @("149.154.160.0/20","91.108.4.0/22","91.108.8.0/22","91.108.56.0/22","95.161.64.0/20") -Protocol Any -Profile Any -ErrorAction SilentlyContinue|Out-Null')
$S.Add('    New-NetFirewallRule -DisplayName "XNET-VPN-UDP" -Direction Outbound -Action Block -Protocol UDP -RemotePort @(1194,51820) -Profile Any -ErrorAction SilentlyContinue|Out-Null')
$S.Add('    New-NetFirewallRule -DisplayName "XNET-Block-QUIC" -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Profile Any -ErrorAction SilentlyContinue|Out-Null')
$S.Add('    Log "Firewall added"')
$S.Add('}')
$S.Add('ipconfig /flushdns | Out-Null')
$S.Add('@{installed=$true;paused=$false;base_sites_enabled=$P.base_sites_enabled;google_search_enabled=$P.google_search_enabled;last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss");user=$UserEmail;allowed=$ok;version="12.0"} | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')
$S.Add('Log "=== DONE $ok domains ==="')
$S.Add('$lc=Get-Content $LOG -ErrorAction SilentlyContinue; if($lc -and $lc.Count -gt 300){$lc[-300..-1]|Out-File $LOG -Encoding UTF8 -Force}')
[IO.File]::WriteAllLines("$DIR\sync.ps1", $S, $utf8)
Write-Host "[+] sync.ps1 written ($($S.Count) lines, $(( Get-Item "$DIR\sync.ps1").Length) bytes)" -ForegroundColor Green

# כתוב tray.ps1
$T = [System.Collections.Generic.List[string]]::new()
$T.Add('$mutex = New-Object System.Threading.Mutex($false,"Global\XNET_TRAY_MUTEX")')
$T.Add('if (-not $mutex.WaitOne(0,$false)) { exit }')
$T.Add('Add-Type -AssemblyName System.Windows.Forms,System.Drawing')
$T.Add('$n = New-Object System.Windows.Forms.NotifyIcon')
$T.Add('$n.Icon = [System.Drawing.SystemIcons]::Shield')
$T.Add('$n.Visible = $true; $n.Text = "X-NET Active"')
$T.Add('function Sync { Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\XNET\sync.ps1`"" -Verb RunAs -ErrorAction SilentlyContinue }')
$T.Add('function RefreshTray {')
$T.Add('    $f="C:\XNET\status.json"')
$T.Add('    if(Test-Path $f){try{$s=Get-Content $f -Raw|ConvertFrom-Json')
$T.Add('        if($s.paused){$n.Icon=[System.Drawing.SystemIcons]::Warning;$t="X-NET Paused"}')
$T.Add('        else{$n.Icon=[System.Drawing.SystemIcons]::Shield;$t="X-NET|"+$s.allowed+" domains|"+$s.last_updated}')
$T.Add('        if($t.Length -gt 63){$t=$t.Substring(0,60)+"..."}; $n.Text=$t')
$T.Add('    }catch{$n.Text="X-NET Active"}}')
$T.Add('}')
$T.Add('$m=New-Object System.Windows.Forms.ContextMenu')
$T.Add('$i1=New-Object System.Windows.Forms.MenuItem "Refresh Now"')
$T.Add('$i1.add_Click({$n.Text="Syncing...";Sync;Start-Sleep 15;RefreshTray})')
$T.Add('$i2=New-Object System.Windows.Forms.MenuItem "View Log"')
$T.Add('$i2.add_Click({if(Test-Path "C:\XNET\sync_log.txt"){Start-Process notepad "C:\XNET\sync_log.txt"}})')
$T.Add('$i3=New-Object System.Windows.Forms.MenuItem "Dashboard"')
$T.Add('$i3.add_Click({$e="";if(Test-Path "C:\XNET\user.txt"){$e=(Get-Content "C:\XNET\user.txt" -First 1).Trim()};Start-Process "https://meny0583285502.github.io/X-NET/?user=$e"})')
$T.Add('$i4=New-Object System.Windows.Forms.MenuItem "Exit"')
$T.Add('$i4.add_Click({$n.Visible=$false;[System.Windows.Forms.Application]::Exit()})')
$T.Add('$i1,$i2,$i3|ForEach-Object{$m.MenuItems.Add($_)|Out-Null}')
$T.Add('$m.MenuItems.Add("-")|Out-Null; $m.MenuItems.Add($i4)|Out-Null')
$T.Add('$n.ContextMenu=$m')
$T.Add('$n.add_DoubleClick({$e="";if(Test-Path "C:\XNET\user.txt"){$e=(Get-Content "C:\XNET\user.txt" -First 1).Trim()};Start-Process "https://meny0583285502.github.io/X-NET/?user=$e"})')
$T.Add('$tmr=New-Object System.Windows.Forms.Timer;$tmr.Interval=30000')
$T.Add('$tmr.add_Tick({RefreshTray});$tmr.Start();RefreshTray')
$T.Add('$f=New-Object System.Windows.Forms.Form;$f.ShowInTaskbar=$false;$f.WindowState="Minimized"')
$T.Add('[System.Windows.Forms.Application]::Run($f)')
[IO.File]::WriteAllLines("$DIR\tray.ps1", $T, $utf8)
Write-Host "[+] tray.ps1 written." -ForegroundColor Green

# Startup shortcut
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$sc.TargetPath = "powershell.exe"
$sc.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$sc.Save()

# הרג tray ישן + הפעל חדש
Get-WmiObject Win32_Process -Filter "name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "tray\.ps1" } |
    ForEach-Object { $_.Terminate() | Out-Null }
Start-Sleep 1
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
Write-Host "[+] Tray started." -ForegroundColor Green

# Scheduled Task
schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
schtasks /create /tn "XNET_Sync" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\sync.ps1`"" /sc minute /mo 1 /ru "SYSTEM" /f | Out-Null
Write-Host "[+] Task created." -ForegroundColor Green

# הרץ sync עכשיו
Write-Host "[+] Running sync..." -ForegroundColor Yellow
& "$DIR\sync.ps1"

# תוצאות
Write-Host ""
Write-Host "=== C:\XNET ===" -ForegroundColor Cyan
Get-ChildItem $DIR | ForEach-Object { Write-Host "  $($_.Name) | $($_.Length)b" }
Write-Host ""
Write-Host "=== LOG ===" -ForegroundColor Cyan
if (Test-Path "$DIR\sync_log.txt") { Get-Content "$DIR\sync_log.txt" | Write-Host -ForegroundColor Yellow }
else { Write-Host "  no log" -ForegroundColor Red }
Read-Host "Press Enter"
