@echo off
title �A�������z�ȹC�ɯ� - ��� Backend
cd /d "%~dp0backend"

if not exist ".venv\Scripts\activate.bat" (
    echo [���~] �䤣��������� .venv, �Х��� README �إ����ҡC
    echo   python -m venv .venv
    echo   .\.venv\Scripts\Activate.ps1
    echo   pip install -r requirements.txt
    pause
    exit /b 1
)

call ".venv\Scripts\activate.bat"

echo ==================================================
echo   �A�������z�ȹC�ɯ�P���|�հt�t�� - ���
echo   API ��� : http://127.0.0.1:8000/docs
echo   ���d�ˬd : http://127.0.0.1:8000/health
echo   ����A�� : �� Ctrl + C
echo ==================================================
echo.

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

echo.
echo [��ݤw����]
pause
