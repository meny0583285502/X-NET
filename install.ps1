Write-Host "[5] Applying True Whitelist to Chrome & Edge..." -ForegroundColor Yellow

# מערך של נתיבי הדפדפנים ברג'יסטרי
$BrowserPaths = @(
    "HKLM:\SOFTWARE\Policies\Google\Chrome",
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
)

foreach ($Path in $BrowserPaths) {
    if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }

    # שלב א': חסימת כל האתרים בעולם (*)
    $BlockPath = "$Path\URLBlocklist"
    if (-not (Test-Path $BlockPath)) { New-Item $BlockPath -Force | Out-Null }
    Set-ItemProperty -Path $BlockPath -Name "1" -Value "*" -Force

    # שלב ב': בניית הרשימה הלבנה מהמשתנה $Allowed
    $AllowPath = "$Path\URLAllowlist"
    
    # ניקוי רשימה ישנה למניעת התנגשויות
    if (Test-Path $AllowPath) { Remove-Item $AllowPath -Recurse -Force }
    New-Item $AllowPath -Force | Out-Null

    $i = 1
    foreach ($domain in $Allowed) {
        Set-ItemProperty -Path $AllowPath -Name $i.ToString() -Value $domain -Force
        $i++
    }
    
    # שלב ג' (אופציונלי): הוספת אתר הניהול שלך כדף בית כפוי
    Set-ItemProperty -Path $Path -Name "RestoreOnStartup" -Value 4 -Type DWord -Force
    $StartupUrlsPath = "$Path\RestoreOnStartupURLs"
    if (-not (Test-Path $StartupUrlsPath)) { New-Item $StartupUrlsPath -Force | Out-Null }
    Set-ItemProperty -Path $StartupUrlsPath -Name "1" -Value "https://meny0583285502.github.io/X-NET/" -Force
}

Write-Host "    Policies applied successfully." -ForegroundColor Green
