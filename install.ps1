# 1. נעילת DNS לכתובות המקומיות - כולל IPv6 למניעת דליפות של אפליקציות
Write-Host "Locking DNS (IPv4 & IPv6)..." -ForegroundColor Yellow
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object {
    try {
        Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses ("127.0.0.1", "::1")
    } catch {}
}

# 2. יישום חסימת URL Disabler דרך הרג'יסטרי לדפדפנים (כרום ואדג')
Write-Host "Applying Browser Policies (True Whitelist)..." -ForegroundColor Yellow

$ChromePath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
$EdgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

foreach ($Path in @($ChromePath, $EdgePath)) {
    if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }

    # שלב א': חסימת הכל כברירת מחדל
    $BlockPath = "$Path\URLBlocklist"
    if (-not (Test-Path $BlockPath)) { New-Item $BlockPath -Force | Out-Null }
    Set-ItemProperty -Path $BlockPath -Name "1" -Value "*" -Force

    # שלב ב': הוספת האתרים המורשים מהמערכת שלך
    $AllowPath = "$Path\URLAllowlist"
    
    # מחיקת רשימה קודמת כדי למנוע שאריות במידה והוסרו אתרים מהפרופיל
    if (Test-Path $AllowPath) { Remove-Item $AllowPath -Recurse -Force }
    New-Item $AllowPath -Force | Out-Null

    $i = 1
    # לולאה שעוברת על הרשימה הלבנה שהורדת מהשרת (המשתנה $Allowed מהסקריפט המקורי)
    foreach ($domain in $Allowed) { 
        Set-ItemProperty -Path $AllowPath -Name $i.ToString() -Value $domain -Force
        $i++
    }
}

Write-Host "Done! Browser policies applied." -ForegroundColor Green
