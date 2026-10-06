#!/usr/bin/env bash
# Smart Tourism Navigation - Backend launcher (Linux / macOS)
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND="$DIR/backend"
VENV="$BACKEND/.venv"
PY="$VENV/bin/python"

echo "============================================================"
echo "  Smart Tourism Navigation - Backend Launcher"
echo "============================================================"
echo

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERROR] python3 not found. Please install Python 3.11+ first."
  exit 1
fi

if [ ! -x "$PY" ]; then
  echo "[1/3] First run: creating Python environment..."
  python3 -m venv "$VENV"
  echo "[2/3] Installing packages (needs internet, may take several minutes)..."
  "$PY" -m pip install --upgrade pip
  "$PY" -m pip install -r "$BACKEND/requirements.txt"
fi

[ -f "$BACKEND/.env" ] || cp "$BACKEND/.env.example" "$BACKEND/.env"

echo "[3/3] Starting backend at http://127.0.0.1:8000"
echo "      Keep this window OPEN while using the app. Press Ctrl+C to stop."
echo
cd "$BACKEND"
exec "$PY" -m uvicorn app.main:app --host 127.0.0.1 --port 8000
