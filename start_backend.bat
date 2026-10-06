@echo off
title 適應型智慧旅遊導航 - 後端 Backend
cd /d "%~dp0backend"

if not exist ".venv\Scripts\activate.bat" (
    echo [錯誤] 找不到虛擬環境 .venv, 請先依 README 建立環境。
    echo   python -m venv .venv
    echo   .\.venv\Scripts\Activate.ps1
    echo   pip install -r requirements.txt
    pause
    exit /b 1
)

call ".venv\Scripts\activate.bat"

echo ==================================================
echo   適應型智慧旅遊導航與路徑調配系統 - 後端
echo   API 文件 : http://127.0.0.1:8000/docs
echo   健康檢查 : http://127.0.0.1:8000/health
echo   停止服務 : 按 Ctrl + C
echo ==================================================
echo.

uvicorn app.main:app --reload --port 8000

echo.
echo [後端已停止]
pause
