@echo off
title 適應型智慧旅遊導航 - App (Chrome)
cd /d "%~dp0frontend"

echo ==================================================
echo   適應型智慧旅遊導航與路徑調配系統 - App
echo   目標裝置 : Chrome 瀏覽器 (Web)
echo   停止 App : 在此視窗按 q, 或直接關閉視窗
echo   提醒     : 請先確認後端已在 8000 埠執行
echo ==================================================
echo.

call flutter pub get
call flutter run -d chrome

echo.
echo [App 已結束]
pause
