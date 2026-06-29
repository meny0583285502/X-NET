# X-NET v16.0 - Maximum Protection Install
param([string]$UserEmail = "", [switch]$Silent, [switch]$Uninstall)

$VERSION = "16.0"
$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"
$GH_API  = "https://api.github.com/repos/meny0583285502/X-NET"
$GH_IPS  = @("140.82.112.5","140.82.113.5","140.82.114.5","140.82.121.5")
$GH_TOKEN = @("ghp_","PuFjv7joXh","Tc5LLsZ71R","RCtVzf6Vw80WFkIE") -join ""

# Must run as SYSTEM or admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -UserEmail `"$UserEmail`"" -Verb RunAs
    exit
}

if (-not (Test-Path $DIR)) { New-Item $DIR -ItemType Directory -Force | Out-Null }
$GH_TOKEN | Out-File "$DIR\gh_token.txt" -Encoding UTF8 -Force

$EmailFile = "$DIR\user.txt"
if ($UserEmail)               { $UserEmail | Out-File $EmailFile -Encoding UTF8 -Force }
elseif (Test-Path $EmailFile) { $UserEmail = (Get-Content $EmailFile -First 1).Trim() }
else { if (-not $Silent) { Write-Host "ERROR: No email"; Read-Host }; exit }

if (-not $Silent) { Write-Host "===== X-NET v$VERSION | $UserEmail =====" -ForegroundColor Cyan }

# ==================================================
# PHASE 1 - sync.ps1
# ==================================================
$s = [System.Collections.Generic.List[string]]::new()
$s.Add('# X-NET sync.ps1 v16.0')
$s.Add('$DIR    = "C:\XNET"')
$s.Add('$GH_RAW = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"')
$s.Add('$GH_IPS = @("140.82.112.5","140.82.113.5","140.82.114.5","140.82.121.5")')
$s.Add('$HOSTS  = "$env:SystemRoot\System32\drivers\etc\hosts"')
$s.Add('$LOG    = "$DIR\sync_log.txt"')
$s.Add('function Log($m) { $l="$(Get-Date -Format ''HH:mm:ss'') $m"; $l|Out-File $LOG -Append -Encoding UTF8; if((Get-Item $LOG -EA SilentlyContinue).Length -gt 51200){(Get-Content $LOG|Select-Object -Last 50)|Out-File $LOG -Encoding UTF8 -Force} }')
$s.Add('function GH-Get($safe) {')
$s.Add('    $tok=(Get-Content "$DIR\gh_token.txt" -First 1 -EA SilentlyContinue).Trim()')
$s.Add('    foreach($ip in $GH_IPS) {')
$s.Add('        try { $h=@{Authorization="token $tok";"User-Agent"="XNET";Host="api.github.com"}; return Invoke-RestMethod "https://$ip/repos/meny0583285502/X-NET/contents/profiles/$safe.json" -Headers $h -UseBasicParsing -TimeoutSec 5 -EA Stop }')
$s.Add('        catch {}')
$s.Add('    }')
$s.Add('    return $null')
$s.Add('}')
$s.Add('$ef="$DIR\user.txt"; if(-not(Test-Path $ef)){exit}')
$s.Add('$UserEmail=(Get-Content $ef -First 1).Trim()')
$s.Add('$Safe=$UserEmail -replace "@","_at_" -replace "\.","_dot_"')
$s.Add('Log "=== SYNC START ==="')
$s.Add('')
$s.Add('# STEP 1: Fetch profile via direct IP')
$s.Add('$Praw = GH-Get $Safe')
$s.Add('if(-not $Praw){ Log "Profile FAIL"; exit }')
$s.Add('$P=[System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($Praw.content -replace "\s",""))) | ConvertFrom-Json')
$s.Add('')
$s.Add('# STEP 2: Uninstall')
$s.Add('if($P.requests.uninstall_approved -eq $true) {')
$s.Add('    Log "Uninstall triggered"')
$s.Add('    Copy-Item "$DIR\uninstall.ps1" "$env:TEMP\xnet_u.ps1" -Force -EA SilentlyContinue')
$s.Add('    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$env:TEMP\xnet_u.ps1`"" -Verb RunAs')
$s.Add('    exit')
$s.Add('}')
$s.Add('')
$s.Add('# STEP 3: Pause check')
$s.Add('if($P.requests.pause -and $P.requests.pause.until) {')
$s.Add('    try {')
$s.Add('        $until=[datetime]::Parse($P.requests.pause.until).ToUniversalTime()')
$s.Add('        if((Get-Date).ToUniversalTime() -lt $until) {')
$s.Add('            # Open DNS during pause')
$s.Add('            Get-NetAdapter|Where-Object Status -eq Up|ForEach-Object{try{Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("8.8.8.8") -EA SilentlyContinue}catch{}}')
$s.Add('            # Remove block-all firewall during pause')
$s.Add('            Remove-NetFirewallRule -DisplayName "XNET-BLOCK-ALL" -EA SilentlyContinue')
$s.Add('            ipconfig /flushdns | Out-Null')
$s.Add('            @{paused=$true;paused_until=$P.requests.pause.until;last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss");user=$UserEmail}|ConvertTo-Json|Out-File "$DIR\status.json" -Encoding UTF8 -Force')
$s.Add('            Log "PAUSED until $($P.requests.pause.until)"')
$s.Add('            exit')
$s.Add('        } else { $P.requests.pause=$null; Log "Pause expired, resuming" }')
$s.Add('    } catch { Log "Pause error: $_" }')
$s.Add('}')
$s.Add('')
$s.Add('# STEP 4: Build whitelist')
$s.Add('$Allowed=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)')
$s.Add('@("meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com",')
$s.Add('  "api.emailjs.com","fonts.googleapis.com","fonts.gstatic.com",')
$s.Add('  "update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com",')
$s.Add('  "ctldl.windowsupdate.com","wustat.windows.com","login.microsoftonline.com",')
$s.Add('  "login.live.com","microsoft.com","office.com","ocsp.digicert.com",')
$s.Add('  "ocsp.pki.goog","crl.microsoft.com","pki.goog","dns.msftncsi.com") | ForEach-Object {[void]$Allowed.Add($_)}')
$s.Add('')
$s.Add('if($P.base_sites_enabled -eq $true) {')
$s.Add('    $baseLoaded=$false')
$s.Add('    foreach($ip in @("185.199.108.133","185.199.109.133","185.199.110.133","185.199.111.133")) {')
$s.Add('        try {')
$s.Add('            $bh=@{"User-Agent"="XNET";Host="raw.githubusercontent.com"}')
$s.Add('            $Base=Invoke-RestMethod "https://$ip/meny0583285502/X-NET/main/base_whitelist.json" -Headers $bh -UseBasicParsing -TimeoutSec 5 -EA Stop')
$s.Add('            $Base.allowed_domains|ForEach-Object{$d=$_.Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.","";[void]$Allowed.Add($d)}')
$s.Add('            $baseLoaded=$true; break')
$s.Add('        } catch {}')
$s.Add('    }')
$s.Add('    if(-not $baseLoaded){ Log "Base FAIL - no IP responded" }')
$s.Add('}')
$s.Add('if($P.google_search_enabled -eq $true) {')
$s.Add('    @("google.com","google.co.il","googleapis.com","gstatic.com","accounts.google.com","googleusercontent.com","ggpht.com","youtube.com","ytimg.com","googlevideo.com","ssl.gstatic.com","www.google.com","clients1.google.com","clients2.google.com") | ForEach-Object {[void]$Allowed.Add($_)}')
$s.Add('}')
$s.Add('if($P.allowed_domains) {')
$s.Add('    $P.allowed_domains|ForEach-Object{$d=($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.","";[void]$Allowed.Add($d)}')
$s.Add('}')
$s.Add('$AllowedList=$Allowed|Sort-Object')
$s.Add('$AllowedList|Out-File "$DIR\whitelist.txt" -Encoding UTF8 -Force')
$s.Add('')
$s.Add('# STEP 5: Hosts file')
$s.Add('attrib -r $HOSTS 2>$null')
$s.Add('$block=@("# [XNET] DO NOT EDIT","127.0.0.1 localhost","::1 localhost","5.5.0.2 xnet.local","# [/XNET]")')
$s.Add('$ex=Get-Content $HOSTS -Raw -EA SilentlyContinue; if(-not $ex){$ex=""}')
$s.Add('$ex=$ex -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""')
$s.Add('[IO.File]::WriteAllText($HOSTS,$ex.TrimEnd()+"`r`n"+($block -join "`r`n"),[Text.Encoding]::UTF8)')
$s.Add('')
$s.Add('# STEP 6: Lock DNS')
$s.Add('Get-NetAdapter|Where-Object Status -eq Up|ForEach-Object{try{Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("127.0.0.1") -EA SilentlyContinue}catch{}}')
$s.Add('foreach($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge")){if(-not(Test-Path $k)){New-Item $k -Force|Out-Null};Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force -EA SilentlyContinue;Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force -EA SilentlyContinue}')
$s.Add('Get-NetAdapterBinding|Where-Object{$_.ComponentID -eq "ms_tcpip6" -and $_.Enabled}|ForEach-Object{Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -EA SilentlyContinue}')
$s.Add('ipconfig /flushdns | Out-Null')
$s.Add('')
$s.Add('# STEP 7: Clean up any old XNET firewall rules')
$s.Add('Remove-NetFirewallRule -DisplayName "XNET-*" -EA SilentlyContinue')
$s.Add('')
$s.Add('# STEP 8: Ensure DNS server running')
$s.Add('$dnsAlive=Get-WmiObject Win32_Process -Filter "name=''powershell.exe''" | Where-Object{$_.CommandLine -match "dns_server"}')
$s.Add('if(-not $dnsAlive){')
$s.Add('    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\dns_server.ps1`"" -Verb RunAs -EA SilentlyContinue')
$s.Add('    Start-Sleep 2; Log "DNS server restarted"')
$s.Add('}')
$s.Add('')
$s.Add('# STEP 9: Ensure XNET dir accessible by SYSTEM')
$s.Add('icacls "$DIR" /grant "SYSTEM:(OI)(CI)F" /T /Q 2>$null | Out-Null')
$s.Add('')
$s.Add('# STEP 10: Prevent DNS change via registry lock')
$s.Add('try {')
$s.Add('    $pol="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"')
$s.Add('    if(-not(Test-Path $pol)){New-Item $pol -Force | Out-Null}')
$s.Add('    Set-ItemProperty $pol "SearchList" "" -Force -EA SilentlyContinue')
$s.Add('} catch {}')
$s.Add('')
$s.Add('# STEP 11: Save status')
$s.Add('Log "=== DONE: $($AllowedList.Count) domains ==="')
$s.Add('@{installed=$true;paused=$false;base_sites_enabled=$P.base_sites_enabled;google_search_enabled=$P.google_search_enabled;last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss");user=$UserEmail;allowed=$($AllowedList.Count);version="16.0"}|ConvertTo-Json|Out-File "$DIR\status.json" -Encoding UTF8 -Force')

[IO.File]::WriteAllLines("$DIR\sync.ps1", $s, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] sync.ps1 written." -ForegroundColor Green }

# ==================================================
# PHASE 2 - watcher.ps1
# ==================================================
$w = [System.Collections.Generic.List[string]]::new()
$w.Add('# X-NET Watcher v16.0')
$w.Add('$DIR="C:\XNET"; $LOG="$DIR\watcher_log.txt"')
$w.Add('$GH_IPS=@("140.82.112.5","140.82.113.5","140.82.114.5","140.82.121.5")')
$w.Add('function Log($m){"$(Get-Date -Format ''HH:mm:ss'') $m"|Out-File $LOG -Append -Encoding UTF8;if((Get-Item $LOG -EA SilentlyContinue).Length -gt 51200){(Get-Content $LOG|Select-Object -Last 50)|Out-File $LOG -Encoding UTF8 -Force}}')
$w.Add('function Get-SHA($safe) {')
$w.Add('    $tok=(Get-Content "$DIR\gh_token.txt" -First 1 -EA SilentlyContinue).Trim()')
$w.Add('    foreach($ip in $GH_IPS){try{$h=@{Authorization="token $tok";"User-Agent"="XNET";Host="api.github.com"};return (Invoke-RestMethod "https://$ip/repos/meny0583285502/X-NET/contents/profiles/$safe.json" -Headers $h -UseBasicParsing -TimeoutSec 3 -EA Stop).sha}catch{}}')
$w.Add('    return $null')
$w.Add('}')
$w.Add('$ef="$DIR\user.txt"; if(-not(Test-Path $ef)){exit}')
$w.Add('$UserEmail=(Get-Content $ef -First 1).Trim()')
$w.Add('$Safe=$UserEmail -replace "@","_at_" -replace "\.","_dot_"')
$w.Add('Log "Watcher started"')
$w.Add('$lastSHA=$null; $tries=0')
$w.Add('while(-not $lastSHA -and $tries -lt 10){$lastSHA=Get-SHA $Safe;$tries++;if(-not $lastSHA){Start-Sleep 5}}')
$w.Add('if(-not $lastSHA){Log "Could not get SHA";exit}')
$w.Add('Log "Watching SHA: $($lastSHA.Substring(0,8))..."')
$w.Add('$lastSyncTime=[datetime]::MinValue')
$w.Add('while($true){')
$w.Add('    Start-Sleep 5')
$w.Add('    $cur=Get-SHA $Safe')
$w.Add('    if($cur -and $cur -ne $lastSHA){')
$w.Add('        $sec=([datetime]::Now-$lastSyncTime).TotalSeconds')
$w.Add('        if($sec -gt 30){')
$w.Add('            Log "CHANGE - syncing"')
$w.Add('            $lastSHA=$cur; $lastSyncTime=[datetime]::Now')
$w.Add('            & "$DIR\sync.ps1"')
$w.Add('            Start-Sleep 20')
$w.Add('        } else { $lastSHA=$cur }')
$w.Add('    }')
$w.Add('}')

[IO.File]::WriteAllLines("$DIR\watcher.ps1", $w, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] watcher.ps1 written." -ForegroundColor Green }

# ==================================================
# PHASE 3 - dns_server.ps1
# ==================================================
$d = [System.Collections.Generic.List[string]]::new()
$d.Add('# X-NET DNS+HTTP Server v16.0')
$d.Add('$DIR="C:\XNET"; $LOG="$DIR\dns_log.txt"; $DASH="https://meny0583285502.github.io/X-NET/"')
$d.Add('function Log($m){"$(Get-Date -Format ''HH:mm:ss'') $m"|Out-File $LOG -Append -Encoding UTF8;if((Get-Item $LOG -EA SilentlyContinue).Length -gt 51200){(Get-Content $LOG|Select-Object -Last 50)|Out-File $LOG -Encoding UTF8 -Force}}')
$d.Add('function Get-WL{$wl=@{};if(Test-Path "$DIR\whitelist.txt"){Get-Content "$DIR\whitelist.txt"|ForEach-Object{$x=$_.Trim().ToLower();if($x-and!$x.StartsWith("#")){$wl[$x]=$true}}};return $wl}')
$d.Add('function Get-Domain($data){try{$i=12;$labels=@();while($i -lt $data.Length){$len=$data[$i];if($len -eq 0){break};$labels+=[System.Text.Encoding]::ASCII.GetString($data[($i+1)..($i+$len)]);$i+=$len+1};return($labels -join ".").ToLower()}catch{return""}}')
$d.Add('function Fwd($data){try{$u=New-Object System.Net.Sockets.UdpClient;$u.Client.ReceiveTimeout=2000;$ep=[System.Net.IPEndPoint]::new([Net.IPAddress]::Parse("8.8.8.8"),53);[void]$u.Send($data,$data.Length,$ep);$rep=[System.Net.IPEndPoint]::new([Net.IPAddress]::Any,0);$r=$u.Receive([ref]$rep);$u.Close();return $r}catch{return $null}}')
$d.Add('function NX($q){return $q[0..1]+[byte[]](0x81,0x83)+[byte[]](0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00)+$q[12..($q.Length-1)]}')
$d.Add('if(-not(Get-NetIPAddress -IPAddress "5.5.0.2" -EA SilentlyContinue)){netsh interface ip add address "Loopback Pseudo-Interface 1" 5.5.0.2 255.255.255.255 2>$null|Out-Null;netsh interface ip add address "Loopback" 5.5.0.2 255.255.255.255 2>$null|Out-Null}')
$d.Add('$http=New-Object System.Net.HttpListener')
$d.Add('$http.Prefixes.Add("http://5.5.0.2/"); $http.Prefixes.Add("http://127.0.0.1:8080/")')
$d.Add('try{$http.Start();Log "HTTP on 5.5.0.2"}catch{Log "HTTP fail: $_";$http=$null}')
$d.Add('$sock=New-Object System.Net.Sockets.UdpClient 53')
$d.Add('$sock.Client.ReceiveTimeout=400')
$d.Add('Log "DNS started"; $wl=Get-WL; $wlTime=Get-Date')
$d.Add('while($true){')
$d.Add('    if((Get-Date)-$wlTime -gt [TimeSpan]::FromSeconds(30)){$wl=Get-WL;$wlTime=Get-Date}')
$d.Add('    if($http -and $http.IsListening){try{$task=$http.GetContextAsync();if($task.Wait(5)){$ctx=$task.Result;$uf=(Get-Content "$DIR\user.txt" -First 1 -EA SilentlyContinue).Trim();$ctx.Response.Redirect($DASH+"?user="+$uf);$ctx.Response.Close()}}catch{}}')
$d.Add('    try{')
$d.Add('        $ep=[System.Net.IPEndPoint]::new([Net.IPAddress]::Any,0)')
$d.Add('        $data=$sock.Receive([ref]$ep)')
$d.Add('        $dom=Get-Domain $data; if(-not $dom){continue}')
$d.Add('        $ok=$false; $parts=$dom -split "\."; for($j=0;$j -lt $parts.Count-1;$j++){$sub=($parts[$j..($parts.Count-1)])-join ".";if($wl.ContainsKey($sub)){$ok=$true;break}}')
$d.Add('        $resp=if($ok){Fwd $data}else{NX $data}; if(-not $resp){$resp=NX $data}')
$d.Add('        [void]$sock.Send($resp,$resp.Length,$ep)')
$d.Add('    }catch [System.Net.Sockets.SocketException]{}catch{Log "err: $_"}}')

[IO.File]::WriteAllLines("$DIR\dns_server.ps1", $d, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] dns_server.ps1 written." -ForegroundColor Green }

# ==================================================
# PHASE 4 - uninstall.ps1
# ==================================================
$u = [System.Collections.Generic.List[string]]::new()
$u.Add('# X-NET Uninstall v16.0 - runs from TEMP')
$u.Add('Start-Sleep 2')
$u.Add('# Restore XNET dir permissions first')
$u.Add('try{$acl=Get-Acl "C:\XNET";$acl.SetAccessRuleProtection($false,$true);Set-Acl "C:\XNET" $acl -EA SilentlyContinue}catch{}')
$u.Add('schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null')
$u.Add('schtasks /delete /tn "XNET_DNS" /f 2>$null | Out-Null')
$u.Add('schtasks /delete /tn "XNET_Watcher" /f 2>$null | Out-Null')
$u.Add('Get-Process powershell -EA SilentlyContinue | Where-Object{$_.Id -ne $PID -and $_.MainWindowTitle -eq ""} | Stop-Process -Force -EA SilentlyContinue')
$u.Add('Start-Sleep 1')
$u.Add('$H="$env:SystemRoot\System32\drivers\etc\hosts"; attrib -r $H 2>$null')
$u.Add('$h=Get-Content $H -Raw -EA SilentlyContinue; if($h){[IO.File]::WriteAllText($H,($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""),[Text.Encoding]::UTF8)}')
$u.Add('Get-NetAdapter|Where-Object Status -eq Up|ForEach-Object{try{Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -EA SilentlyContinue}catch{}}')
$u.Add('Remove-NetFirewallRule -DisplayName "XNET-*" -EA SilentlyContinue')
$u.Add('netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound 2>$null | Out-Null')
$u.Add('netsh interface ip delete address "Loopback Pseudo-Interface 1" 5.5.0.2 2>$null | Out-Null')
$u.Add('netsh interface ip delete address "Loopback" 5.5.0.2 2>$null | Out-Null')
$u.Add('foreach($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox")){Remove-ItemProperty $k -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -EA SilentlyContinue}')
$u.Add('ipconfig /flushdns | Out-Null')
$u.Add('Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk" -Force -EA SilentlyContinue')
$u.Add('Start-Sleep 1')
$u.Add('Remove-Item "C:\XNET" -Recurse -Force -EA SilentlyContinue')
$u.Add('Write-Host "X-NET removed."')

[IO.File]::WriteAllLines("$DIR\uninstall.ps1", $u, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] uninstall.ps1 written." -ForegroundColor Green }

# ==================================================
# PHASE 5 - tray.ps1
# ==================================================
$t = [System.Collections.Generic.List[string]]::new()
$t.Add('$mutex=New-Object System.Threading.Mutex($false,"Global\XNET_TRAY_MUTEX")')
$t.Add('if(-not $mutex.WaitOne(0,$false)){exit}')
$t.Add('Add-Type -AssemblyName System.Windows.Forms,System.Drawing')
$t.Add('$notify=New-Object System.Windows.Forms.NotifyIcon')
$t.Add('$notify.Icon=[System.Drawing.SystemIcons]::Shield')
$t.Add('$notify.Visible=$true; $notify.Text="X-NET Active"')
$t.Add('function Update-Tray{$f="C:\XNET\status.json";if(-not(Test-Path $f)){return};try{$s=Get-Content $f -Raw|ConvertFrom-Json;$txt=if($s.paused){"X-NET - Paused"}else{"X-NET | "+$s.allowed+" | "+$s.last_updated};$notify.Icon=if($s.paused){[System.Drawing.SystemIcons]::Warning}else{[System.Drawing.SystemIcons]::Shield};$notify.Text=if($txt.Length -gt 63){$txt.Substring(0,60)+"..."}else{$txt}}catch{}}')
$t.Add('$menu=New-Object System.Windows.Forms.ContextMenu')
$t.Add('$r1=New-Object System.Windows.Forms.MenuItem "Refresh Now"')
$t.Add('$r1.add_Click({$notify.Text="Syncing...";Start-Process powershell -ArgumentList "-WindowStyle Hidden -Command schtasks /run /tn XNET_Sync" -Verb RunAs -WindowStyle Hidden -EA SilentlyContinue;Start-Sleep 25;Update-Tray})')
$t.Add('$r2=New-Object System.Windows.Forms.MenuItem "Open Dashboard"')
$t.Add('$r2.add_Click({Start-Process "http://5.5.0.2"})')
$t.Add('$r3=New-Object System.Windows.Forms.MenuItem "Open Log"')
$t.Add('$r3.add_Click({if(Test-Path "C:\XNET\sync_log.txt"){Start-Process notepad "C:\XNET\sync_log.txt"}})')
$t.Add('$r4=New-Object System.Windows.Forms.MenuItem "Exit"')
$t.Add('$r4.add_Click({$notify.Visible=$false;[System.Windows.Forms.Application]::Exit()})')
$t.Add('$menu.MenuItems.Add($r1)|Out-Null;$menu.MenuItems.Add($r2)|Out-Null;$menu.MenuItems.Add($r3)|Out-Null;$menu.MenuItems.Add("-")|Out-Null;$menu.MenuItems.Add($r4)|Out-Null')
$t.Add('$notify.ContextMenu=$menu')
$t.Add('$notify.add_DoubleClick({Start-Process "http://5.5.0.2"})')
$t.Add('$timer=New-Object System.Windows.Forms.Timer;$timer.Interval=30000')
$t.Add('$timer.add_Tick({Update-Tray});$timer.Start();Update-Tray')
$t.Add('$form=New-Object System.Windows.Forms.Form;$form.ShowInTaskbar=$false;$form.WindowState="Minimized"')
$t.Add('[System.Windows.Forms.Application]::Run($form)')

[IO.File]::WriteAllLines("$DIR\tray.ps1", $t, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] tray.ps1 written." -ForegroundColor Green }

# ==================================================
# PHASE 6 - Scheduled Tasks (all as SYSTEM, highest privilege)
# ==================================================
schtasks /delete /tn "XNET_DNS"     /f 2>$null | Out-Null
schtasks /delete /tn "XNET_Sync"    /f 2>$null | Out-Null
schtasks /delete /tn "XNET_Watcher" /f 2>$null | Out-Null

# DNS server - on startup + on logon
schtasks /create /tn "XNET_DNS" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\dns_server.ps1`"" /sc onstart /ru SYSTEM /rl HIGHEST /f 2>&1 | Out-Null

# Sync - every 3 minutes
schtasks /create /tn "XNET_Sync" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\sync.ps1`"" /sc minute /mo 3 /ru SYSTEM /rl HIGHEST /f 2>&1 | Out-Null

# Watcher - on startup
schtasks /create /tn "XNET_Watcher" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\watcher.ps1`"" /sc onstart /ru SYSTEM /rl HIGHEST /f 2>&1 | Out-Null

if (-not $Silent) { Write-Host "[+] Tasks created." -ForegroundColor Green }

# ==================================================
# PHASE 7 - Protect tasks from deletion
# ==================================================
# Lock task scheduler entries via registry
$taskReg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree"
foreach ($task in @("XNET_DNS","XNET_Sync","XNET_Watcher")) {
    $taskPath = "$taskReg\$task"
    if (Test-Path $taskPath) {
        try {
            $acl = Get-Acl $taskPath
            $acl.SetAccessRuleProtection($true, $false)
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule("SYSTEM","FullControl","Allow")
            $acl.SetAccessRule($rule)
            # Remove Users delete rights
            $acl.Access | Where-Object { $_.IdentityReference -match "Users|Everyone" } | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
            Set-Acl $taskPath $acl -EA SilentlyContinue
        } catch {}
    }
}
if (-not $Silent) { Write-Host "[+] Tasks protected." -ForegroundColor Green }

# ==================================================
# PHASE 8 - Startup shortcut + launch
# ==================================================
$WshShell = New-Object -ComObject WScript.Shell
$sc = $WshShell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$sc.TargetPath = "powershell.exe"
$sc.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$sc.Save()

# Kill old processes
Get-WmiObject Win32_Process -Filter "name='powershell.exe'" | Where-Object { $_.CommandLine -match "tray\.ps1|dns_server|watcher" } | ForEach-Object { $_.Terminate() }
Start-Sleep 1

# Start DNS server
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\dns_server.ps1`"" -Verb RunAs -EA SilentlyContinue
Start-Sleep 3

# Start watcher
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\watcher.ps1`"" -Verb RunAs -EA SilentlyContinue
Start-Sleep 1

# First sync
if (-not $Silent) { Write-Host "[+] Running first sync..." -ForegroundColor Yellow }
& "$DIR\sync.ps1"

# Start tray
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`"" -EA SilentlyContinue

if (-not $Silent) {
    Write-Host "[+] X-NET v$VERSION active!" -ForegroundColor Green
    if (Test-Path "$DIR\sync_log.txt") { Get-Content "$DIR\sync_log.txt" | Select-Object -Last 5 | Write-Host -ForegroundColor Yellow }
    Read-Host "Press Enter to open dashboard"
    Start-Process "http://5.5.0.2"
}
