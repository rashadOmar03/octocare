# Rebuild Flutter web and pick up changes automatically (no manual cache bump).
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $root "smart_clinic")

Write-Host "Building Flutter web (release)..." -ForegroundColor Cyan
flutter build web --release

Write-Host ""
Write-Host "Done. If uvicorn is already running, restart it once." -ForegroundColor Green
Write-Host "Then open the app and refresh normally — hard refresh is not required." -ForegroundColor Green
