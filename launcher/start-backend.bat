@echo off
setlocal
cd /d "%~dp0"
title Smart Tourism Navigation - Backend

echo ============================================================
echo   Smart Tourism Navigation - Backend Launcher
echo   (Chinese user guide: the .txt file in this folder)
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

echo [3/3] Starting backend at http://127.0.0.1:8000
echo       Keep this window OPEN while using the app. Press Ctrl+C to stop.
echo.
pushd "%BACKEND%"
"%PY%" -m uvicorn app.main:app --host 127.0.0.1 --port 8000
popd
echo.
echo Backend stopped.
pause
