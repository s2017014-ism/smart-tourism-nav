@echo off
setlocal
cd /d "%~dp0"
title Smart Tourism Navigation - Web Version

echo ============================================================
echo   Smart Tourism Navigation - Web Version
echo ============================================================
echo.

set "BACKEND=%~dp0backend"
set "PY=%BACKEND%\.venv\Scripts\python.exe"

where python >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Python not found.
  echo Please install Python 3.11+ from https://www.python.org/downloads/
  echo and tick "Add python.exe to PATH" during installation.
  echo.
  pause
  exit /b 1
)

if not exist "%PY%" (
  echo [1/3] First run: creating Python environment...
  python -m venv "%BACKEND%\.venv"
  if errorlevel 1 ( echo [ERROR] Failed to create venv. & pause & exit /b 1 )
  echo [2/3] Installing packages ^(needs internet, may take several minutes^)...
  "%PY%" -m pip install --upgrade pip
  "%PY%" -m pip install -r "%BACKEND%\requirements.txt"
  if errorlevel 1 (
    echo [ERROR] Package installation failed. Check your network and retry.
    pause
    exit /b 1
  )
)

if not exist "%BACKEND%\.env" copy /Y "%BACKEND%\.env.example" "%BACKEND%\.env" >nul

echo [3/3] Starting web version...
echo   Local : http://127.0.0.1:8000/
echo   LAN   : http://YOUR-PC-IP:8000/   (same Wi-Fi)
echo   Keep this window OPEN. Press Ctrl+C to stop.
echo.

rem Wait until /health is ready, then open the browser automatically.
start "" powershell -NoProfile -WindowStyle Hidden -Command "for($i=0;$i -lt 90;$i++){try{$r=Invoke-WebRequest http://127.0.0.1:8000/health -UseBasicParsing -TimeoutSec 2; if($r.StatusCode -eq 200){Start-Process http://127.0.0.1:8000/; break}}catch{}; Start-Sleep -Seconds 2}"

pushd "%BACKEND%"
"%PY%" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
popd
echo.
echo Web server stopped.
pause
