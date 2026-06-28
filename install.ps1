# X-NET v13.0 - install.ps1
# Architecture: Local DNS filter (no IP-based firewall)
param([string]$UserEmail = "", [switch]$Silent)

$VERSION = "13.0"
$DIR     = "C:\XNET"
$HOSTS   = "$env:SystemRoot\System32\drivers\etc\hosts"
$GH_RAW  = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"
$XNET_IP = "5.5.0.2"

if (-not (Test-Path $DIR)) { New-Item $DIR -ItemType Directory -Force | Out-Null }

$EmailFile = "$DIR\user.txt"
if ($UserEmail)               { $UserEmail | Out-File $EmailFile -Encoding UTF8 -Force }
elseif (Test-Path $EmailFile) { $UserEmail = (Get-Content $EmailFile -First 1).Trim() }
else { if (-not $Silent) { Write-Host "ERROR: No email"; Read-Host }; exit }

if (-not $Silent) { Write-Host "===== X-NET v$VERSION | $UserEmail =====" -ForegroundColor Cyan }

# ==================================================
# PHASE 1 - Write dns_server.ps1
# Minimal DNS server: resolves whitelist -> real IP, everything else -> NXDOMAIN
# ==================================================
$dnsLines = [System.Collections.Generic.List[string]]::new()
$dnsLines.Add('# X-NET DNS Server v13.0')
$dnsLines.Add('$DIR = "C:\XNET"')
$dnsLines.Add('$XNET_IP = "5.5.0.2"')
$dnsLines.Add('$LOG = "$DIR\dns_log.txt"')
$dnsLines.Add('function Log($m) { "$(Get-Date -Format ''HH:mm:ss'') $m" | Out-File $LOG -Append -Encoding UTF8 }')
$dnsLines.Add('')
$dnsLines.Add('# Load whitelist')
$dnsLines.Add('function Get-Whitelist {')
$dnsLines.Add('    $wl = @{}')
$dnsLines.Add('    $f = "$DIR\whitelist.txt"')
$dnsLines.Add('    if (Test-Path $f) {')
$dnsLines.Add('        Get-Content $f | ForEach-Object {')
$dnsLines.Add('            $d = $_.Trim().ToLower()')
$dnsLines.Add('            if ($d -and -not $d.StartsWith("#")) { $wl[$d] = $true }')
$dnsLines.Add('        }')
$dnsLines.Add('    }')
$dnsLines.Add('    return $wl')
$dnsLines.Add('}')
$dnsLines.Add('')
$dnsLines.Add('# DNS response builder')
$dnsLines.Add('function Build-DNS-Response($query, $ip, $isBlock) {')
$dnsLines.Add('    # Parse query ID from first 2 bytes')
$dnsLines.Add('    $id = $query[0..1]')
$dnsLines.Add('    if ($isBlock) {')
$dnsLines.Add('        # NXDOMAIN response')
$dnsLines.Add('        $flags = [byte[]](0x81,0x83)')
$dnsLines.Add('        $resp = $id + $flags + [byte[]](0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00)')
$dnsLines.Add('        $resp += $query[12..($query.Length-1)]')
$dnsLines.Add('        return $resp')
$dnsLines.Add('    } else {')
$dnsLines.Add('        # A record response')
$dnsLines.Add('        $flags = [byte[]](0x81,0x80)')
$dnsLines.Add('        $ipBytes = ([Net.IPAddress]$ip).GetAddressBytes()')
$dnsLines.Add('        $resp = $id + $flags + [byte[]](0x00,0x01,0x00,0x01,0x00,0x00,0x00,0x00)')
$dnsLines.Add('        $qSection = $query[12..($query.Length-1)]')
$dnsLines.Add('        $resp += $qSection')
$dnsLines.Add('        # Answer: pointer to question + A record')
$dnsLines.Add('        $resp += [byte[]](0xC0,0x0C,0x00,0x01,0x00,0x01,0x00,0x00,0x00,0x3C,0x00,0x04)')
$dnsLines.Add('        $resp += $ipBytes')
$dnsLines.Add('        return $resp')
$dnsLines.Add('    }')
$dnsLines.Add('}')
$dnsLines.Add('')
$dnsLines.Add('# Extract domain from DNS query')
$dnsLines.Add('function Get-Domain($data) {')
$dnsLines.Add('    try {')
$dnsLines.Add('        $i = 12; $labels = @()')
$dnsLines.Add('        while ($i -lt $data.Length) {')
$dnsLines.Add('            $len = $data[$i]')
$dnsLines.Add('            if ($len -eq 0) { break }')
$dnsLines.Add('            $labels += [System.Text.Encoding]::ASCII.GetString($data[($i+1)..($i+$len)])')
$dnsLines.Add('            $i += $len + 1')
$dnsLines.Add('        }')
$dnsLines.Add('        return ($labels -join ".").ToLower()')
$dnsLines.Add('    } catch { return "" }')
$dnsLines.Add('}')
$dnsLines.Add('')
$dnsLines.Add('# Forward DNS query to real resolver')
$dnsLines.Add('function Forward-DNS($data, $upstream) {')
$dnsLines.Add('    try {')
$dnsLines.Add('        $udp = New-Object System.Net.Sockets.UdpClient')
$dnsLines.Add('        $udp.Client.ReceiveTimeout = 3000')
$dnsLines.Add('        $ep = [System.Net.IPEndPoint]::new([Net.IPAddress]::Parse($upstream), 53)')
$dnsLines.Add('        [void]$udp.Send($data, $data.Length, $ep)')
$dnsLines.Add('        $repEP = [System.Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)')
$dnsLines.Add('        $resp = $udp.Receive([ref]$repEP)')
$dnsLines.Add('        $udp.Close()')
$dnsLines.Add('        return $resp')
$dnsLines.Add('    } catch { return $null }')
$dnsLines.Add('}')
$dnsLines.Add('')
$dnsLines.Add('# Main DNS loop')
$dnsLines.Add('$upstream = "8.8.8.8"')
$dnsLines.Add('$socket = New-Object System.Net.Sockets.UdpClient 53')
$dnsLines.Add('$socket.Client.ReceiveTimeout = 1000')
$dnsLines.Add('Log "DNS Server started on 127.0.0.1:53"')
$dnsLines.Add('$wl = Get-Whitelist')
$dnsLines.Add('$wlTime = Get-Date')
$dnsLines.Add('')
$dnsLines.Add('while ($true) {')
$dnsLines.Add('    # Reload whitelist every 60 seconds')
$dnsLines.Add('    if ((Get-Date) - $wlTime -gt [TimeSpan]::FromSeconds(60)) {')
$dnsLines.Add('        $wl = Get-Whitelist')
$dnsLines.Add('        $wlTime = Get-Date')
$dnsLines.Add('    }')
$dnsLines.Add('    try {')
$dnsLines.Add('        $ep = [System.Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)')
$dnsLines.Add('        $data = $socket.Receive([ref]$ep)')
$dnsLines.Add('        $domain = Get-Domain $data')
$dnsLines.Add('        if (-not $domain) { continue }')
$dnsLines.Add('        # Check if domain or parent is whitelisted')
$dnsLines.Add('        $allowed = $false')
$dnsLines.Add('        $parts = $domain -split "\."')
$dnsLines.Add('        for ($j = 0; $j -lt $parts.Count - 1; $j++) {')
$dnsLines.Add('            $sub = ($parts[$j..($parts.Count-1)]) -join "."')
$dnsLines.Add('            if ($wl.ContainsKey($sub)) { $allowed = $true; break }')
$dnsLines.Add('        }')
$dnsLines.Add('        if ($allowed) {')
$dnsLines.Add('            # Special: xnet.local -> dashboard IP')
$dnsLines.Add('            if ($domain -eq "xnet.local") {')
$dnsLines.Add('                $resp = Build-DNS-Response $data $XNET_IP $false')
$dnsLines.Add('            } else {')
$dnsLines.Add('                $resp = Forward-DNS $data $upstream')
$dnsLines.Add('                if (-not $resp) { $resp = Build-DNS-Response $data "" $true }')
$dnsLines.Add('            }')
$dnsLines.Add('        } else {')
$dnsLines.Add('            $resp = Build-DNS-Response $data "" $true')
$dnsLines.Add('        }')
$dnsLines.Add('        if ($resp) { [void]$socket.Send($resp, $resp.Length, $ep) }')
$dnsLines.Add('    } catch [System.Net.Sockets.SocketException] {')
$dnsLines.Add('        # Timeout - normal, continue')
$dnsLines.Add('    } catch { Log "DNS error: $_" }')
$dnsLines.Add('}')

[IO.File]::WriteAllLines("$DIR\dns_server.ps1", $dnsLines, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] dns_server.ps1 written ($($dnsLines.Count) lines)." -ForegroundColor Green }

# ==================================================
# PHASE 2 - Write sync.ps1
# ==================================================
$syncLines = [System.Collections.Generic.List[string]]::new()
$syncLines.Add('# X-NET sync.ps1 v13.0')
$syncLines.Add('$DIR    = "C:\XNET"')
$syncLines.Add('$GH_RAW = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"')
$syncLines.Add('$LOG    = "$DIR\sync_log.txt"')
$syncLines.Add('$HOSTS  = "$env:SystemRoot\System32\drivers\etc\hosts"')
$syncLines.Add('$XNET_IP = "5.5.0.2"')
$syncLines.Add('function Log($m) { "$(Get-Date -Format ''HH:mm:ss'') $m" | Out-File $LOG -Append -Encoding UTF8 }')
$syncLines.Add('')
$syncLines.Add('$EmailFile = "$DIR\user.txt"')
$syncLines.Add('if (-not (Test-Path $EmailFile)) { exit }')
$syncLines.Add('$UserEmail = (Get-Content $EmailFile -First 1).Trim()')
$syncLines.Add('$Safe = $UserEmail -replace "@","_at_" -replace "\.","_dot_"')
$syncLines.Add('')
$syncLines.Add('# STEP 1: Temporarily point DNS to real resolver to reach GitHub')
$syncLines.Add('Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {')
$syncLines.Add('    try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("8.8.8.8") -ErrorAction SilentlyContinue } catch {}')
$syncLines.Add('}')
$syncLines.Add('ipconfig /flushdns | Out-Null')
$syncLines.Add('Start-Sleep -Seconds 2')
$syncLines.Add('')
$syncLines.Add('# STEP 2: Fetch profile from GitHub')
$syncLines.Add('try {')
$syncLines.Add('    $P = Invoke-RestMethod "$GH_RAW/profiles/$Safe.json" -UseBasicParsing -ErrorAction Stop')
$syncLines.Add('} catch {')
$syncLines.Add('    Log "Profile FAIL: $_"')
$syncLines.Add('    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {')
$syncLines.Add('        try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue } catch {}')
$syncLines.Add('    }')
$syncLines.Add('    ipconfig /flushdns | Out-Null')
$syncLines.Add('    exit')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('# STEP 3: Full uninstall')
$syncLines.Add('if ($P.requests.uninstall_approved -eq $true) {')
$syncLines.Add('    Log "Uninstall triggered"')
$syncLines.Add('    schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null')
$syncLines.Add('    schtasks /delete /tn "XNET_DNS" /f 2>$null | Out-Null')
$syncLines.Add('    Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "" } | Stop-Process -Force -ErrorAction SilentlyContinue')
$syncLines.Add('    Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue } catch {} }')
$syncLines.Add('    Remove-NetFirewallRule -DisplayName "XNET-*" -ErrorAction SilentlyContinue')
$syncLines.Add('    attrib -r $HOSTS 2>$null')
$syncLines.Add('    $h = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue')
$syncLines.Add('    if ($h) { [IO.File]::WriteAllText($HOSTS, ($h -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?",""), [Text.Encoding]::UTF8) }')
$syncLines.Add('    foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKLM:\SOFTWARE\Policies\Mozilla\Firefox")) {')
$syncLines.Add('        Remove-ItemProperty $k -Name "DnsOverHttpsMode","BuiltInDnsClientEnabled","DNSOverHTTPS" -ErrorAction SilentlyContinue')
$syncLines.Add('    }')
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
$syncLines.Add('            Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddress -ErrorAction SilentlyContinue } catch {} }')
$syncLines.Add('            ipconfig /flushdns | Out-Null')
$syncLines.Add('            @{ paused=$true; paused_until=$P.requests.pause.until; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')
$syncLines.Add('            Log "PAUSED until $($P.requests.pause.until)"')
$syncLines.Add('            exit')
$syncLines.Add('        }')
$syncLines.Add('    } catch {}')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('# STEP 5: Build whitelist')
$syncLines.Add('$Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)')
$syncLines.Add('$systemDomains = @(')
$syncLines.Add('    "meny0583285502.github.io","raw.githubusercontent.com","github.com","api.github.com",')
$syncLines.Add('    "googleapis.com","gstatic.com","accounts.google.com","googleusercontent.com",')
$syncLines.Add('    "api.emailjs.com","fonts.googleapis.com","fonts.gstatic.com",')
$syncLines.Add('    "update.microsoft.com","windowsupdate.microsoft.com","download.windowsupdate.com",')
$syncLines.Add('    "ctldl.windowsupdate.com","wustat.windows.com","login.microsoftonline.com",')
$syncLines.Add('    "login.live.com","microsoft.com","office.com","ocsp.digicert.com",')
$syncLines.Add('    "ocsp.pki.goog","crl.microsoft.com","pki.goog","dns.msftncsi.com","xnet.local"')
$syncLines.Add(')')
$syncLines.Add('$systemDomains | ForEach-Object { [void]$Allowed.Add($_) }')
$syncLines.Add('')
$syncLines.Add('if ($P.base_sites_enabled -eq $true) {')
$syncLines.Add('    try {')
$syncLines.Add('        $Base = Invoke-RestMethod "$GH_RAW/base_whitelist.json" -UseBasicParsing -ErrorAction Stop')
$syncLines.Add('        $Base.allowed_domains | ForEach-Object {')
$syncLines.Add('            $d = $_.Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d)')
$syncLines.Add('        }')
$syncLines.Add('    } catch { Log "Base whitelist FAIL: $_" }')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('if ($P.google_search_enabled -eq $true) {')
$syncLines.Add('    "google.com","google.co.il","googleapis.com","ggpht.com","gstatic.com","youtube.com","ytimg.com","googlevideo.com","googleusercontent.com","google-analytics.com" | ForEach-Object { [void]$Allowed.Add($_) }')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('if ($P.allowed_domains) {')
$syncLines.Add('    $P.allowed_domains | ForEach-Object {')
$syncLines.Add('        $d = ($_ -split "\|")[0].Trim() -replace "^https?://","" -replace "/$","" -replace "^www\.",""; [void]$Allowed.Add($d)')
$syncLines.Add('    }')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('$AllowedList = $Allowed | Sort-Object')
$syncLines.Add('$AllowedList | Out-File "$DIR\whitelist.txt" -Encoding UTF8 -Force')
$syncLines.Add('Log "Whitelist: $($AllowedList.Count) domains"')
$syncLines.Add('')
$syncLines.Add('# STEP 6: Write hosts - add 5.5.0.2 for xnet.local + dashboard redirect')
$syncLines.Add('attrib -r $HOSTS 2>$null')
$syncLines.Add('$block = [System.Collections.Generic.List[string]]::new()')
$syncLines.Add('$block.Add("# [XNET] DO NOT EDIT")')
$syncLines.Add('$block.Add("127.0.0.1 localhost")')
$syncLines.Add('$block.Add("::1 localhost")')
$syncLines.Add('$block.Add("5.5.0.2 xnet.local")')
$syncLines.Add('$block.Add("# [/XNET]")')
$syncLines.Add('$existing = Get-Content $HOSTS -Raw -ErrorAction SilentlyContinue; if (-not $existing) { $existing = "" }')
$syncLines.Add('$existing = $existing -replace "(?s)# \[XNET\].*?# \[/XNET\]\r?\n?", ""')
$syncLines.Add('[IO.File]::WriteAllText($HOSTS, $existing.TrimEnd() + "`r`n" + ($block -join "`r`n"), [Text.Encoding]::UTF8)')
$syncLines.Add('')
$syncLines.Add('# STEP 7: Lock DNS to 127.0.0.1 (our DNS server)')
$syncLines.Add('Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {')
$syncLines.Add('    try { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses @("127.0.0.1") -ErrorAction SilentlyContinue } catch {}')
$syncLines.Add('}')
$syncLines.Add('# Block DoH in browsers')
$syncLines.Add('foreach ($k in @("HKLM:\SOFTWARE\Policies\Google\Chrome","HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {')
$syncLines.Add('    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }')
$syncLines.Add('    Set-ItemProperty $k "DnsOverHttpsMode" "off" -Force -ErrorAction SilentlyContinue')
$syncLines.Add('    Set-ItemProperty $k "BuiltInDnsClientEnabled" 0 -Type DWord -Force -ErrorAction SilentlyContinue')
$syncLines.Add('}')
$syncLines.Add('# Disable IPv6')
$syncLines.Add('Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled } | ForEach-Object {')
$syncLines.Add('    Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue')
$syncLines.Add('}')
$syncLines.Add('ipconfig /flushdns | Out-Null')
$syncLines.Add('')
$syncLines.Add('# STEP 8: Make sure DNS server task is running')
$syncLines.Add('$dnsTask = schtasks /query /tn "XNET_DNS" 2>$null')
$syncLines.Add('if (-not $dnsTask) {')
$syncLines.Add('    schtasks /create /tn "XNET_DNS" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\XNET\dns_server.ps1\"" /sc onstart /ru "SYSTEM" /f 2>&1 | Out-Null')
$syncLines.Add('}')
$syncLines.Add('# Check if DNS server process is alive')
$syncLines.Add('$dnsProc = Get-WmiObject Win32_Process -Filter "name=''powershell.exe''" | Where-Object { $_.CommandLine -match "dns_server" }')
$syncLines.Add('if (-not $dnsProc) {')
$syncLines.Add('    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\XNET\dns_server.ps1`"" -Verb RunAs -ErrorAction SilentlyContinue')
$syncLines.Add('    Start-Sleep -Seconds 2')
$syncLines.Add('    Log "DNS server restarted"')
$syncLines.Add('}')
$syncLines.Add('')
$syncLines.Add('# STEP 9: Save status')
$syncLines.Add('Log "=== DONE: $($AllowedList.Count) domains ==="')
$syncLines.Add('@{ installed=$true; paused=$false; base_sites_enabled=$P.base_sites_enabled; google_search_enabled=$P.google_search_enabled; last_updated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); user=$UserEmail; allowed=$($AllowedList.Count); version="13.0" } | ConvertTo-Json | Out-File "$DIR\status.json" -Encoding UTF8 -Force')

[IO.File]::WriteAllLines("$DIR\sync.ps1", $syncLines, [Text.Encoding]::UTF8)
if (-not $Silent) { Write-Host "[+] sync.ps1 written ($($syncLines.Count) lines)." -ForegroundColor Green }

# ==================================================
# PHASE 3 - Write tray.ps1
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
$trayLines.Add('$r1.add_Click({ $notify.Text = "X-NET - Syncing..."; schtasks /run /tn "XNET_Sync" 2>$null | Out-Null; Start-Sleep 35; Update-Tray })')
$trayLines.Add('$r2 = New-Object System.Windows.Forms.MenuItem "Open Dashboard"')
$trayLines.Add('$r2.add_Click({ Start-Process "http://xnet.local" })')
$trayLines.Add('$r3 = New-Object System.Windows.Forms.MenuItem "Open Log"')
$trayLines.Add('$r3.add_Click({ if (Test-Path "C:\XNET\sync_log.txt") { Start-Process notepad "C:\XNET\sync_log.txt" } })')
$trayLines.Add('$r4 = New-Object System.Windows.Forms.MenuItem "Exit Tray"')
$trayLines.Add('$r4.add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() })')
$trayLines.Add('$menu.MenuItems.Add($r1) | Out-Null')
$trayLines.Add('$menu.MenuItems.Add($r2) | Out-Null')
$trayLines.Add('$menu.MenuItems.Add($r3) | Out-Null')
$trayLines.Add('$menu.MenuItems.Add("-") | Out-Null')
$trayLines.Add('$menu.MenuItems.Add($r4) | Out-Null')
$trayLines.Add('$notify.ContextMenu = $menu')
$trayLines.Add('$notify.add_DoubleClick({ Start-Process "http://xnet.local" })')
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

# ==================================================
# PHASE 4 - Scheduled Tasks
# ==================================================
# DNS server - runs at startup as SYSTEM
schtasks /delete /tn "XNET_DNS" /f 2>$null | Out-Null
schtasks /create /tn "XNET_DNS" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\dns_server.ps1`"" /sc onstart /ru "SYSTEM" /f 2>&1 | Out-Null
if (-not $Silent) { Write-Host "[+] XNET_DNS task created (on startup)." -ForegroundColor Green }

# Sync - runs every 5 minutes as SYSTEM
schtasks /delete /tn "XNET_Sync" /f 2>$null | Out-Null
schtasks /create /tn "XNET_Sync" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\sync.ps1`"" /sc minute /mo 5 /ru "SYSTEM" /f 2>&1 | Out-Null
if (-not $Silent) { Write-Host "[+] XNET_Sync task created (every 5 min)." -ForegroundColor Green }

# ==================================================
# PHASE 5 - Tray
# ==================================================
$WshShell = New-Object -ComObject WScript.Shell
$sc = $WshShell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\XNET_Tray.lnk")
$sc.TargetPath = "powershell.exe"
$sc.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`""
$sc.Save()

Get-WmiObject Win32_Process -Filter "name='powershell.exe'" | Where-Object { $_.CommandLine -match "tray\.ps1" } | ForEach-Object { $_.Terminate() }
Start-Sleep 1
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\tray.ps1`"" -ErrorAction SilentlyContinue
if (-not $Silent) { Write-Host "[+] Tray started." -ForegroundColor Green }

# ==================================================
# PHASE 6 - First sync + start DNS server
# ==================================================
if (-not $Silent) { Write-Host "[+] Starting DNS server..." -ForegroundColor Yellow }
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$DIR\dns_server.ps1`"" -Verb RunAs -ErrorAction SilentlyContinue
Start-Sleep 2

if (-not $Silent) { Write-Host "[+] Running first sync..." -ForegroundColor Yellow }
& "$DIR\sync.ps1"

if (-not $Silent) {
    Write-Host "[+] X-NET v$VERSION active!" -ForegroundColor Green
    Write-Host "=== Files in C:\XNET ===" -ForegroundColor Cyan
    Get-ChildItem $DIR -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name) ($($_.Length)b)" }
    Write-Host "=== Last log ===" -ForegroundColor Cyan
    if (Test-Path "$DIR\sync_log.txt") { Get-Content "$DIR\sync_log.txt" | Select-Object -Last 8 | Write-Host -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Dashboard: http://xnet.local OR http://5.5.0.2" -ForegroundColor Cyan
    Read-Host "Press Enter to open dashboard"
    Start-Process "http://xnet.local"
}
