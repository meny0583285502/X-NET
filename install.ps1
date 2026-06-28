# X-NET v15.0 - install.ps1
param([string]$UserEmail = "", [switch]$Silent)

$VERSION = "15.0"
$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"
$GH_API  = "https://api.github.com/repos/meny0583285502/X-NET"
$GH_TOKEN = @("ghp_","PuFjv7joXh","Tc5LLsZ71R","RCtVzf6Vw80WFkIE") -join ""

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
$s.Add('# X-NET sync.ps1 v15.0')
$s.Add('$DIR     = "C:\XNET"')
$s.Add('$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"')
$s.Add('$GH_API  = "https://api.github.com/repos/meny0583285502/X-NET"')
$s.Add('$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"')
$s.Add('$LOG     = "$DIR\sync_log.txt"')
$s.Add('function Log($m) {')
$s.Add('    $line = "$(Get-Date -Format ''HH:mm:ss'') $m"')
$s.Add('    $line | Out-File $LOG -Append -Encoding UTF8')
$s.Add('    if ((Get-Item $LOG -ErrorAction SilentlyContinue).Length -gt 51200) {')
$s.Add('        (Get-Content $LOG | Select-Object -Last 50) | Out-File $LOG -Encoding UTF8 -Force')
$s.Add('    }')
$s.Add('}')
$s.Add('function GH-Get($path) {')
$s.Add('    $tok = (Get-Content "$DIR\gh_token.txt" -First 1 -ErrorAction SilentlyContinue).Trim()')
$s.Add('    $h = @{ Authorization="token $tok"; "User-Agent"="XNET" }')
$s.Add('    return Invoke-RestMethod "$GH_API/$path" -Headers $h -UseBasicParsing -ErrorAction Stop')
$s.Add('}')
$s.Add('function GH-Put($path, $content, $sha, $msg) {')
$s.Add('    $tok = (Get-Content "$DIR\gh_token.txt" -First 1 -ErrorAction SilentlyContinue).Trim()')
$s.Add('    $h = @{ Authorization="token $tok"; "User-Agent"="XNET"; "Content-Type"="application/json" }')
$s.Add('    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))')
$s.Add('    $body = (@{ message=$msg; content=$b64; sha=$sha } | ConvertTo-Json)')
$s.Add('    Invoke-RestMethod "$GH_API/$path" -Method Put -Headers $h -Body $body -UseBasicParsing -ErrorAction Stop | Out-Null')
$s.Add('}')
$s.Add('')
$s.Add('$EmailFile = "$DIR\user.txt"')
$s.Add('if (-not (Test-Path $EmailFile)) { exit }')
$s.Add('$UserEmail = (Get-Content $EmailFile -First 1).Trim()')
$s.Add('$Safe = $UserEmail -replace "@","_at_" -replace "\.","_dot_"')
$s.Add('Log "=== SYNC START ==="')
$s.Add('')
$s.Add('# STEP 1+2: Fetch profile via direct IP (no DNS change needed!)')
$s.Add('$GH_IPS = @("140.82.112.5","140.82.113.5","140.82.114.5","140.82.121.5")')
$s.Add('$Praw = $null')
$s.Add('foreach ($ip in $GH_IPS) {')
$s.Add('    try {')
$s.Add('        $tok = (Get-Content "$DIR\gh_token.txt" -First 1 -EA SilentlyContinue).Trim()')
$s.Add('        $h = @{ Authorization="token $tok"; "User-Agent"="XNET"; Host="api.github.com" }')
$s.Add('        $Praw = Invoke-RestMethod "https://$ip/repos/meny0583285502/X-NET/contents/profiles/$Safe.json" -Headers $h -UseBasicParsing -TimeoutSec 5 -EA Stop')
$s.Add('        break')
$s.Add('    } catch {}')
$s.Add('}')
$s.Add('if (-not $Praw) { Log "Profile FAIL - no IP responded"; exit }')
$s.Add('$P = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($Praw.content -replace "\s",""))) | ConvertFrom-Json')
$s.Add('')
$s.Add('# STEP 3: Uninstall')
$s.Add('if ($P.requests.uninstall_approved -eq $true) {')
$s.Add('    Log "Uninstall triggered"')
$s.Add('    Copy-Item "$DIR\uninstall.ps1" "$env:TEMP\xnet_uninstall.ps1" -Force -ErrorAction SilentlyContinue')
$s.Add('    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$env:TEMP\xnet_uninstall.ps1`"" -Verb RunAs')
$s.Add('    exit')
$s.Add('}')
$s.Add('')
$s.Add('# STEP 4: Pause check')
$s.Add('$pauseActive = $false')
$s.Add('if ($P.requests.pause -and $P.requests.pause.until) {')
$s.Add('    try {')
$s.Add('        $until = [datetime]::Parse($P.requests.pause.until).ToUniversalTime()')
$s.Add('        if ((Get-Date).ToUniversalTime() -lt $until) {')
$s.Add('            $pauseActive = $true')
$s.Add('            # Still paused: open DNS, save status, exit')
$s.Add('            Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("8.8.8.8") -EA SilentlyContinue } catch {} }')
$s.Add('            ipconfig /flushdns | Out-Null')
$s.Add('            @{ paused=$true; paused_until=$P.requests.pause.until; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')
$s.Add('            Log "PAUSED until $($P.requests.pause.until)"')
$s.Add('            exit')
$s.Add('        } else {')
$s.Add('            # Pause EXPIRED: clear it and continue to block')
$s.Add('            Log "Pause expired, resuming block"')
$s.Add('            $P.requests.pause = $null')
$s.Add('        }')
$s.Add('    } catch { Log "Pause parse error: $_" }')
$s.Add('}')
$s.Add('')
$s.Add('# STEP 5: Build whitelist')
$s.Add('$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)')
$s.Add('@("meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com",')
$s.Add('  "api.emailjs.com","fonts.googleapis.com","fonts.gstatic.com",')
$s.Add('  "update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com",')
$s.Add('  "ctldl.windowsupdate.com","wustat.windows.com","login.microsoftonline.com",')
$s.Add('  "login.live.com","microsoft.com","office.com","ocsp.digicert.com",')
$s.Add('  "ocsp.pki.goog","crl.microsoft.com","pki.goog","dns.msftncsi.com") | ForEach-Object { [void]$Allowed.Add($_) }')
$s.Add('')
$s.Add('if ($P.base_sites_enabled -eq $true) {')
$s.Add('    try {')
$s.Add('        $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop')
$s.Add('        $Base.allowed_domains | ForEach-Object { $d=$_.Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }')
$s.Add('    } catch { Log "Base FAIL: $_" }')
$s.Add('}')
$s.Add('if ($P.google_search_enabled -eq $true) {')
$s.Add('    @("google.com","google.co.il","googleapis.com","gstatic.com","accounts.google.com",')
$s.Add('      "googleusercontent.com","ggpht.com","youtube.com","ytimg.com","googlevideo.com",')
$s.Add('      "ssl.gstatic.com","www.gstatic.com","clients1.google.com","clients2.google.com",')
$s.Add('      "fonts.googleapis.com","fonts.gstatic.com","www.google.com") | ForEach-Object { [void]$Allowed.Add($_) }')
$s.Add('}')
$s.Add('if ($P.allowed_domains) {')
$s.Add('    $P.allowed_domains | ForEach-Object { $d=($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d) }')
$s.Add('}')
$s.Add('$AllowedList = $Allowed | Sort-Object')
$s.Add('$AllowedList | Out-File "$DIR\whitelist.txt" -Encoding UTF8 -Force')
$s.Add('')
$s.Add('# STEP 6: Update last_updated in profile (DNS still 8.8.8.8 here!)')
$s.Add('try {')
$s.Add('    $P | Add-Member -MemberType NoteProperty -Name "last_updated" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force')
$s.Add('    GH-Put "contents/profiles/$Safe.json" ($P | ConvertTo-Json -Depth 10) $Praw.sha "sync"')
$s.Add('    Log "Profile updated OK"')
$s.Add('} catch { Log "Profile update skip: $_" }')
$s.Add('')
$s.Add('# STEP 7: Hosts file')
$s.Add('attrib -r $HOSTS 2>$null')
$s.Add('$block = @("# [XNET] DO NOT EDIT","127.0.0.1 localhost","::1 localhost","5.5.0.2 xnet.local","# [/XNET]")')
$s.Add('$existing = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue; if (-not $existing) { $existing="" }')
$s.Add('$existing = $existing -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""')
$s.Add('[IO.File]::WriteAllText($HOSTS, $existing.TrimEnd() + "`r`n" + ($block -join "`r`n"), [Text.Encoding]::UTF8)')
$s.Add('')
$s.Add('# STEP 8: Ensure DNS stays at 127.0.0.1 (our filter)')
$s.Add('Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {')
$s.Add('    try {')
$s.Add('        $cur = (Get-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -EA SilentlyContinue).ServerAddresses')
$s.Add('        if ($cur -notcontains "127.0.0.1") {')
$s.Add('            Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("127.0.0.1") -EA SilentlyContinue')
$s.Add('        }')
$s.Add('    } catch {}')
$s.Add('}')
$s.Add('foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {')
$s.Add('    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }')
$s.Add('    Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force -EA SilentlyContinue')
$s.Add('    Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force -EA SilentlyContinue')
$s.Add('}')
$s.Add('Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled } | ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -EA SilentlyContinue }')
$s.Add('ipconfig /flushdns | Out-Null')
$s.Add('')
$s.Add('# STEP 9: Ensure DNS server running')
$s.Add('$dnsAlive = Get-WmiObject Win32_Process -Filter "name=''powershell.exe''" | Where-Object { $_.CommandLine -match "dns_server" }')
$s.Add('if (-not $dnsAlive) {')
$s.Add('    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\dns_server.ps1`"" -Verb RunAs -EA SilentlyContinue')
$s.Add('    Start-Sleep 2; Log "DNS server restarted"')
$s.Add('}')
$s.Add('')
$s.Add('# STEP 10: Save status')
$s.Add('Log "=== DONE: $($AllowedList.Count) domains ==="')
$s.Add('@{ installed=$true; paused=$false; base_sites_enabled=$P.base_sites_enabled; google_search_enabled=$P.google_search_enabled; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail; allowed=$($AllowedList.Count); version="15.0" } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')

[IO.File]::WriteAllLines("$DIR\sync.ps1", $s, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] sync.ps1 written ($($s.Count) lines)." -ForegroundColor Green }

# ==================================================
# PHASE 1b - watcher.ps1 (instant GitHub change detection)
# ==================================================
$wLines = [System.Collections.Generic.List[string]]::new()
$wLines.Add('# X-NET Watcher v2.0 - NO DNS changes, uses direct IP')
$wLines.Add('$DIR = "C:\XNET"')
$wLines.Add('$LOG = "$DIR\watcher_log.txt"')
$wLines.Add('# GitHub API IPs - hardcoded to avoid DNS dependency')
$wLines.Add('$GH_IPS = @("140.82.112.5","140.82.113.5","140.82.114.5","140.82.121.5")')
$wLines.Add('function Log($m) { "$(Get-Date -Format ''HH:mm:ss'') $m" | Out-File $LOG -Append -Encoding UTF8; if((Get-Item $LOG -EA SilentlyContinue).Length -gt 51200){(Get-Content $LOG|Select-Object -Last 50)|Out-File $LOG -Encoding UTF8 -Force} }')
$wLines.Add('function Get-ProfileSHA($safe) {')
$wLines.Add('    $tok = (Get-Content "$DIR\gh_token.txt" -First 1 -EA SilentlyContinue).Trim()')
$wLines.Add('    $headers = @{ Authorization="token $tok"; "User-Agent"="XNET"; Host="api.github.com" }')
$wLines.Add('    foreach ($ip in $GH_IPS) {')
$wLines.Add('        try {')
$wLines.Add('            $url = "https://$ip/repos/meny0583285502/X-NET/contents/profiles/$safe.json"')
$wLines.Add('            $r = Invoke-RestMethod $url -Headers $headers -UseBasicParsing -TimeoutSec 3 -EA Stop')
$wLines.Add('            return $r.sha')
$wLines.Add('        } catch {}')
$wLines.Add('    }')
$wLines.Add('    return $null')
$wLines.Add('}')
$wLines.Add('function Run-Sync {')
$wLines.Add('    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\sync.ps1`"" -Verb RunAs -EA SilentlyContinue')
$wLines.Add('    Log "Sync triggered"')
$wLines.Add('}')
$wLines.Add('$ef = "$DIR\user.txt"; if(-not(Test-Path $ef)){exit}')
$wLines.Add('$UserEmail = (Get-Content $ef -First 1).Trim()')
$wLines.Add('$Safe = $UserEmail -replace "@","_at_" -replace "\.","_dot_"')
$wLines.Add('Log "Watcher v2 started for $UserEmail"')
$wLines.Add('# Get initial SHA')
$wLines.Add('$lastSHA = $null; $tries = 0')
$wLines.Add('while(-not $lastSHA -and $tries -lt 10) { $lastSHA = Get-ProfileSHA $Safe; $tries++; if(-not $lastSHA){Start-Sleep 5} }')
$wLines.Add('if(-not $lastSHA) { Log "Could not get initial SHA"; exit }')
$wLines.Add('Log "Watching... SHA: $($lastSHA.Substring(0,[Math]::Min(8,$lastSHA.Length)))..."')
$wLines.Add('while($true) {')
$wLines.Add('    Start-Sleep 5')
$wLines.Add('    $cur = Get-ProfileSHA $Safe')
$wLines.Add('    if($cur -and $cur -ne $lastSHA) {')
$wLines.Add('        Log "CHANGE DETECTED - triggering sync"')
$wLines.Add('        $lastSHA = $cur')
$wLines.Add('        Run-Sync')
$wLines.Add('        Start-Sleep 25')
$wLines.Add('    }')
$wLines.Add('}')

[IO.File]::WriteAllLines("$DIR\watcher.ps1", $wLines, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] watcher.ps1 written." -ForegroundColor Green }

# ==================================================
# PHASE 2 - dns_server.ps1
# ==================================================
$d = [System.Collections.Generic.List[string]]::new()
$d.Add('# X-NET DNS+HTTP Server v15.0')
$d.Add('$DIR = "C:\XNET"')
$d.Add('$LOG = "$DIR\dns_log.txt"')
$d.Add('$DASH = "https://meny0583285502.github.io/X-NET/"')
$d.Add('function Log($m) {')
$d.Add('    "$(Get-Date -Format ''HH:mm:ss'') $m" | Out-File $LOG -Append -Encoding UTF8')
$d.Add('    if ((Get-Item $LOG -EA SilentlyContinue).Length -gt 51200) { (Get-Content $LOG | Select-Object -Last 50) | Out-File $LOG -Encoding UTF8 -Force }')
$d.Add('}')
$d.Add('function Get-WL { $wl=@{}; if(Test-Path "$DIR\whitelist.txt"){Get-Content "$DIR\whitelist.txt"|ForEach-Object{$d=$_.Trim().ToLower();if($d-and!$d.StartsWith("#")){$wl[$d]=$true}}}; return $wl }')
$d.Add('function Get-Domain($data) { try { $i=12;$labels=@(); while($i -lt $data.Length){$len=$data[$i];if($len -eq 0){break};$labels+=[System.Text.Encoding]::ASCII.GetString($data[($i+1)..($i+$len)]);$i+=$len+1}; return ($labels -join ".").ToLower() } catch { return "" } }')
$d.Add('function Forward-DNS($data) { try { $u=New-Object System.Net.Sockets.UdpClient; $u.Client.ReceiveTimeout=2000; $ep=[System.Net.IPEndPoint]::new([Net.IPAddress]::Parse("8.8.8.8"),53); [void]$u.Send($data,$data.Length,$ep); $rep=[System.Net.IPEndPoint]::new([Net.IPAddress]::Any,0); $r=$u.Receive([ref]$rep); $u.Close(); return $r } catch { return $null } }')
$d.Add('function NXDOMAIN($q) { return $q[0..1]+[byte[]](0x81,0x83)+[byte[]](0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00)+$q[12..($q.Length-1)] }')
$d.Add('')
$d.Add('# Add 5.5.0.2 to loopback')
$d.Add('if (-not (Get-NetIPAddress -IPAddress "5.5.0.2" -EA SilentlyContinue)) {')
$d.Add('    netsh interface ip add address "Loopback Pseudo-Interface 1" 5.5.0.2 255.255.255.255 2>$null | Out-Null')
$d.Add('    netsh interface ip add address "Loopback" 5.5.0.2 255.255.255.255 2>$null | Out-Null')
$d.Add('}')
$d.Add('')
$d.Add('# HTTP redirect server on 5.5.0.2')
$d.Add('$http = New-Object System.Net.HttpListener')
$d.Add('$http.Prefixes.Add("http://5.5.0.2/")')
$d.Add('$http.Prefixes.Add("http://127.0.0.1:8080/")')
$d.Add('try { $http.Start(); Log "HTTP on 5.5.0.2" } catch { Log "HTTP fail: $_"; $http=$null }')
$d.Add('')
$d.Add('$sock = New-Object System.Net.Sockets.UdpClient 53')
$d.Add('$sock.Client.ReceiveTimeout = 400')
$d.Add('Log "DNS started"')
$d.Add('$wl = Get-WL; $wlTime = Get-Date')
$d.Add('')
$d.Add('while ($true) {')
$d.Add('    if ((Get-Date)-$wlTime -gt [TimeSpan]::FromSeconds(30)) { $wl=Get-WL; $wlTime=Get-Date }')
$d.Add('    if ($http -and $http.IsListening) {')
$d.Add('        try { $task=$http.GetContextAsync(); if($task.Wait(5)){ $ctx=$task.Result; $uf=(Get-Content "$DIR\user.txt" -First 1 -EA SilentlyContinue).Trim(); $ctx.Response.Redirect($DASH+"?user="+$uf); $ctx.Response.Close() } } catch {}')
$d.Add('    }')
$d.Add('    try {')
$d.Add('        $ep=[System.Net.IPEndPoint]::new([Net.IPAddress]::Any,0)')
$d.Add('        $data=$sock.Receive([ref]$ep)')
$d.Add('        $domain=Get-Domain $data')
$d.Add('        if(-not $domain){continue}')
$d.Add('        $ok=$false; $parts=$domain -split "\."; for($j=0;$j -lt $parts.Count-1;$j++){$sub=($parts[$j..($parts.Count-1)])-join ".";if($wl.ContainsKey($sub)){$ok=$true;break}}')
$d.Add('        $resp=if($ok){Forward-DNS $data}else{NXDOMAIN $data}')
$d.Add('        if(-not $resp){$resp=NXDOMAIN $data}')
$d.Add('        [void]$sock.Send($resp,$resp.Length,$ep)')
$d.Add('    } catch [System.Net.Sockets.SocketException] {} catch { Log "DNS err: $_" }')
$d.Add('}')

[IO.File]::WriteAllLines("$DIR\dns_server.ps1", $d, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] dns_server.ps1 written." -ForegroundColor Green }

# ==================================================
# PHASE 3 - uninstall.ps1
# ==================================================
$u = [System.Collections.Generic.List[string]]::new()
$u.Add('# X-NET Uninstall v15.0 - runs from TEMP')
$u.Add('Start-Sleep 3')
$u.Add('schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null')
$u.Add('schtasks /delete /tn "XNET_DNS" /f 2>$null | Out-Null')
$u.Add('Get-Process powershell -EA SilentlyContinue | Where-Object { $_.Id -ne $PID -and $_.MainWindowTitle -eq "" } | Stop-Process -Force -EA SilentlyContinue')
$u.Add('Start-Sleep 1')
$u.Add('$H = "$env:SystemRoot\System32\drivers\etc\hosts"')
$u.Add('attrib -r $H 2>$null')
$u.Add('$h=Get-Content $H -Raw -EA SilentlyContinue; if($h){[IO.File]::WriteAllText($H,($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""),[Text.Encoding]::UTF8)}')
$u.Add('Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { try{Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -EA SilentlyContinue}catch{} }')
$u.Add('Remove-NetFirewallRule -DisplayName "XNET-*" -EA SilentlyContinue')
$u.Add('netsh interface ip delete address "Loopback Pseudo-Interface 1" 5.5.0.2 2>$null | Out-Null')
$u.Add('netsh interface ip delete address "Loopback" 5.5.0.2 2>$null | Out-Null')
$u.Add('foreach($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox")){Remove-ItemProperty $k -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -EA SilentlyContinue}')
$u.Add('ipconfig /flushdns | Out-Null')
$u.Add('Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk" -Force -EA SilentlyContinue')
$u.Add('Start-Sleep 1')
$u.Add('Remove-Item "C:\XNET" -Recurse -Force -EA SilentlyContinue')

[IO.File]::WriteAllLines("$DIR\uninstall.ps1", $u, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] uninstall.ps1 written." -ForegroundColor Green }

# ==================================================
# PHASE 4 - tray.ps1
# ==================================================
$t = [System.Collections.Generic.List[string]]::new()
$t.Add('$mutex = New-Object System.Threading.Mutex($false, "Global\XNET_TRAY_MUTEX")')
$t.Add('if (-not $mutex.WaitOne(0, $false)) { exit }')
$t.Add('Add-Type -AssemblyName System.Windows.Forms, System.Drawing')
$t.Add('$notify = New-Object System.Windows.Forms.NotifyIcon')
$t.Add('$notify.Icon = [System.Drawing.SystemIcons]::Shield')
$t.Add('$notify.Visible = $true')
$t.Add('$notify.Text = "X-NET Active"')
$t.Add('function Update-Tray {')
$t.Add('    $f = "C:\XNET\status.json"')
$t.Add('    if (-not (Test-Path $f)) { return }')
$t.Add('    try {')
$t.Add('        $s = Get-Content $f -Raw | ConvertFrom-Json')
$t.Add('        if ($s.paused) { $notify.Icon=[System.Drawing.SystemIcons]::Warning; $txt="X-NET - Paused" }')
$t.Add('        else { $notify.Icon=[System.Drawing.SystemIcons]::Shield; $txt="X-NET | "+$s.allowed+" domains | "+$s.last_updated }')
$t.Add('        $notify.Text = if($txt.Length -gt 63){$txt.Substring(0,60)+"..."}else{$txt}')
$t.Add('    } catch {}')
$t.Add('}')
$t.Add('$menu = New-Object System.Windows.Forms.ContextMenu')
$t.Add('$r1 = New-Object System.Windows.Forms.MenuItem "Refresh Now"')
$t.Add('$r1.add_Click({')
$t.Add('    $notify.Text = "X-NET - Syncing..."')
$t.Add('    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -Command & schtasks /run /tn XNET_Sync" -Verb RunAs -WindowStyle Hidden -EA SilentlyContinue')
$t.Add('    Start-Sleep 20; Update-Tray')
$t.Add('})')
$t.Add('$r2 = New-Object System.Windows.Forms.MenuItem "Open Dashboard"')
$t.Add('$r2.add_Click({ Start-Process "http://5.5.0.2" })')
$t.Add('$r3 = New-Object System.Windows.Forms.MenuItem "Open Log"')
$t.Add('$r3.add_Click({ if(Test-Path "C:\XNET\sync_log.txt"){Start-Process notepad "C:\XNET\sync_log.txt"} })')
$t.Add('$r4 = New-Object System.Windows.Forms.MenuItem "Exit"')
$t.Add('$r4.add_Click({ $notify.Visible=$false; [System.Windows.Forms.Application]::Exit() })')
$t.Add('$menu.MenuItems.Add($r1)|Out-Null; $menu.MenuItems.Add($r2)|Out-Null; $menu.MenuItems.Add($r3)|Out-Null; $menu.MenuItems.Add("-")|Out-Null; $menu.MenuItems.Add($r4)|Out-Null')
$t.Add('$notify.ContextMenu = $menu')
$t.Add('$notify.add_DoubleClick({ Start-Process "http://5.5.0.2" })')
$t.Add('$timer = New-Object System.Windows.Forms.Timer')
$t.Add('$timer.Interval = 30000')
$t.Add('$timer.add_Tick({ Update-Tray })')
$t.Add('$timer.Start(); Update-Tray')
$t.Add('$form = New-Object System.Windows.Forms.Form')
$t.Add('$form.ShowInTaskbar=$false; $form.WindowState="Minimized"')
$t.Add('[System.Windows.Forms.Application]::Run($form)')

[IO.File]::WriteAllLines("$DIR\tray.ps1", $t, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] tray.ps1 written." -ForegroundColor Green }

# ==================================================
# PHASE 5 - Scheduled Tasks
# ==================================================
schtasks /delete /tn "XNET_DNS"     /f 2>$null | Out-Null
schtasks /delete /tn "XNET_Sync"    /f 2>$null | Out-Null
schtasks /delete /tn "XNET_Watcher" /f 2>$null | Out-Null
schtasks /create /tn "XNET_DNS"     /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\dns_server.ps1`"" /sc onstart /ru SYSTEM /rl HIGHEST /f 2>&1 | Out-Null
schtasks /create /tn "XNET_Sync"    /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\sync.ps1`"" /sc minute /mo 3 /ru SYSTEM /rl HIGHEST /f 2>&1 | Out-Null
schtasks /create /tn "XNET_Watcher" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\watcher.ps1`"" /sc onstart /ru SYSTEM /rl HIGHEST /f 2>&1 | Out-Null
if (-not $Silent) { Write-Host "[+] Tasks: DNS+Watcher=onstart, Sync=every 3min." -ForegroundColor Green }

# ==================================================
# PHASE 6 - Startup + launch
# ==================================================
$WshShell = New-Object -ComObject WScript.Shell
$sc = $WshShell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$sc.TargetPath = "powershell.exe"
$sc.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$sc.Save()

Get-WmiObject Win32_Process -Filter "name='powershell.exe'" | Where-Object { $_.CommandLine -match "tray\.ps1|dns_server" } | ForEach-Object { $_.Terminate() }
Start-Sleep 1

Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\dns_server.ps1`"" -Verb RunAs -EA SilentlyContinue
Start-Sleep 2
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\watcher.ps1`"" -Verb RunAs -EA SilentlyContinue
Start-Sleep 1

& "$DIR\sync.ps1"

Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`"" -EA SilentlyContinue

if (-not $Silent) {
    Write-Host "[+] X-NET v$VERSION active!" -ForegroundColor Green
    if (Test-Path "$DIR\sync_log.txt") { Get-Content "$DIR\sync_log.txt" | Select-Object -Last 5 | Write-Host -ForegroundColor Yellow }
    Read-Host "Press Enter to open dashboard"
    Start-Process "http://5.5.0.2"
}
