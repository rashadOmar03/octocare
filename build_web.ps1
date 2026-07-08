# Rebuild Flutter web and pick up changes automatically (no manual cache bump).
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $root "smart_clinic")

Write-Host "Building Flutter web (release)..." -ForegroundColor Cyan
flutter build web --release
if ($LASTEXITCODE -ne 0) { throw "Flutter web build failed with exit code $LASTEXITCODE" }

$backendWeb = Join-Path (Join-Path $root "backend") "web"
Write-Host "Copying web build to backend/web for Railway..." -ForegroundColor Cyan
if (Test-Path $backendWeb) { Remove-Item $backendWeb -Recurse -Force }
Copy-Item -Path (Join-Path (Join-Path (Get-Location) "build") "web") -Destination $backendWeb -Recurse

'{"app_name":"Octocare Clinic","version":"1.0.1","build_number":"2","package_name":"smart_clinic"}' | Set-Content -Path (Join-Path $backendWeb "version.json") -Encoding UTF8

Write-Host ""
Write-Host "Done. Web output: smart_clinic/build/web" -ForegroundColor Green
Write-Host "Railway bundle: backend/web (commit + push to deploy online web)" -ForegroundColor Green
