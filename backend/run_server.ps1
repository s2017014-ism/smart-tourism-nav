# 啟動後端（會先清掉殘留的 uvicorn 行程，避免佔用 8000 埠）
# 用法：在 backend/ 目錄右鍵「用 PowerShell 執行」，或：
#   cd backend ; .\run_server.ps1

$ErrorActionPreference = "SilentlyContinue"

# 只結束本專案 .venv 啟動的 python 行程
Get-Process python |
    Where-Object { $_.Path -like "*\.venv\Scripts\python*" } |
    ForEach-Object {
        Write-Host "結束殘留行程 PID=$($_.Id)"
        Stop-Process -Id $_.Id -Force
    }

Start-Sleep -Milliseconds 500

Write-Host "啟動後端 http://127.0.0.1:8000 ..."
.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
