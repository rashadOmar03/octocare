# Octocare Clinic - start backend + cloudflare + ESP32 bridge
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Stopping old services..." -ForegroundColor Yellow
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'uvicorn main:app|esp32_tcp_bridge' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

Write-Host "Starting backend on http://0.0.0.0:8000 ..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList @(
  '-NoExit', '-Command',
  "cd '$root\backend'; python -m uvicorn main:app --host 0.0.0.0 --port 8000"
)

Start-Sleep -Seconds 4

Write-Host "Starting Cloudflare tunnel (http2) ..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList @(
  '-NoExit', '-Command',
  "cd '$root'; cloudflared tunnel --url http://127.0.0.1:8000 --protocol http2"
)

Write-Host "Starting ESP32 bridge (10.53.1.57:5000) ..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList @(
  '-NoExit', '-Command',
  "cd '$root'; python backend\tools\esp32_tcp_bridge.py --esp32 10.53.1.57 --port 5000 --backend http://127.0.0.1:8000"
)

Write-Host ""
Write-Host "Done. Open:" -ForegroundColor Green
Write-Host "  PC web:   http://localhost:8000"
Write-Host "  Phone:    http://10.53.1.239:8000  (same WiFi, fastest)"
Write-Host "  Cloudflare URL: copy from the cloudflared window"
Write-Host ""
