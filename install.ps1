# ============================================================
#  X-NET Blocker — סקריפט התקנה, אכיפה וריצה שוטפת
# ============================================================
param (
    [string]$UserEmail = ""
)

$InstallDir = "C:\XNET"
$EmailFile = "$InstallDir\user.txt"
$HostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"

# 1. יצירת תיקיית עבודה ושמירת זיהוי מקומי
if (-not (Test-Path $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}

if ($UserEmail -ne "") {
    $UserEmail | Out-File $EmailFile -Force
} elseif (Test-Path $EmailFile) {
    $UserEmail = Get-Content $EmailFile | Select-Object -First 1
} else {
    Write-Warning "לא נמצא אימייל מזהה. הסקריפט עוצר."
    exit
}

$SafeEmail = $UserEmail -replace '@', '_at_'
# שימוש ב-Raw כדי למנוע בעיות מטמון (Cache) של GitHub Pages
$JsonUrl = "https://raw.githubusercontent.com/meny0583285502/X-NET/main/profiles/$SafeEmail.json"

Write-Host "מושך הגדרות עבור: $UserEmail"

# 2. קריאת נתוני הפרופיל מ-GitHub
try {
    $ProfileData = Invoke-RestMethod -Uri $JsonUrl -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Warning "שגיאה בתקשורת מול השרת. ממשיך עם ההגדרות הקיימות."
    exit
}

# 3. מנגנון השמדה עצמית (אם אושרה הסרה)
if ($ProfileData.requests.uninstall_approved -eq $true) {
    Write-Host "✅ התקבל אישור הסרה! מנקה את המערכת..." -ForegroundColor Green
    
    # מחיקת חסימות מ-Hosts
    $HostsContent = Get-Content $HostsFile -Raw
    $HostsContent = $HostsContent -replace "(?s)# \[X-NET-START\].*?# \[X-NET-END\]\r?\n?", ""
    $HostsContent | Set-Content $HostsFile -Encoding UTF8

    ipconfig /flushdns | Out-Null
    schtasks /delete /tn "XNET_Blocker" /f 2>$null
    
    Write-Host "התוכנה הוסרה. מוחק קבצים מקומיים..."
    Start-Sleep -Seconds 2
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

# 4. הכנת רשימת החסימות
Write-Host "מעדכן רשימות חסימה..."
$BlockLines = @("# [X-NET-START] - נא לא לערוך ידנית")
foreach ($Domain in $ProfileData.blocked_domains) {
    $BlockLines += "127.0.0.1 $Domain"
    $BlockLines += "127.0.0.1 www.$Domain"
}
$BlockLines += "# [X-NET-END]"
$BlockText = $BlockLines -join [Environment]::NewLine

# 5. החלת החסימות על קובץ ה-Hosts (עדכון בלוק קיים או הוספת חדש)
$HostsContent = Get-Content $HostsFile -Raw
if ($HostsContent -match "(?s)# \[X-NET-START\].*?# \[X-NET-END\]") {
    $HostsContent = $HostsContent -replace "(?s)# \[X-NET-START\].*?# \[X-NET-END\]", $BlockText
} else {
    $HostsContent = $HostsContent + [Environment]::NewLine + $BlockText
}
$HostsContent | Set-Content $HostsFile -Encoding UTF8

# ניקוי מטמון DNS כדי שהחסימה תעבוד מיד
ipconfig /flushdns | Out-Null

# 6. רישום משימה מתוזמנת (רק אם לא קיימת)
$TaskCheck = schtasks /query /tn "XNET_Blocker" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "רושם משימת הפעלה אוטומטית..."
    $Action = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/meny0583285502/X-NET/main/install.ps1' -OutFile 'C:\XNET\run.ps1'; & 'C:\XNET\run.ps1'`""
    schtasks /create /tn "XNET_Blocker" /tr $Action /sc onlogon /rl highest /f > $null
}

Write-Host "✅ מערכת X-NET מעודכנת ופעילה!" -ForegroundColor Cyan