# X-NET Installer - Run this file
param([string]$UserEmail = "")
$GH_RAW = "https://raw.githubusercontent.com/meny0583285502/X-NET/main"

# If not admin - relaunch self with UAC
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrator")) {
    $self = $MyInvocation.MyCommand.Path
    $emailArg = if ($UserEmail) { "-UserEmail `"$UserEmail`"" } else { "" }
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$self`" $emailArg"
    exit
}

# Now running as admin - download and run real script
Write-Host "X-NET Setup - Downloading..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri "$GH_RAW/install.ps1" -OutFile "$env:TEMP\xnet_main.ps1" -UseBasicParsing -ErrorAction Stop
    & "$env:TEMP\xnet_main.ps1" -UserEmail $UserEmail
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Read-Host "Press Enter to close"
}
