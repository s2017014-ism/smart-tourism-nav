#!/usr/bin/env bash
# Smart Tourism Navigation - Web version launcher (Linux / macOS)
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND="$DIR/backend"
VENV="$BACKEND/.venv"
PY="$VENV/bin/python"

echo "============================================================"
echo "  Smart Tourism Navigation - Web Version"
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

echo "[3/3] Starting web version..."
echo "  Local : http://127.0.0.1:8000/"
echo "  LAN   : http://YOUR-PC-IP:8000/   (same Wi-Fi)"
echo "  Keep this window OPEN. Press Ctrl+C to stop."
echo

# Wait until the backend is ready, then open the browser.
(
  for _ in $(seq 1 90); do
    if command -v curl >/dev/null 2>&1; then
      curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1 && break
    else
      sleep 2
      break
    fi
    sleep 2
  done
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open http://127.0.0.1:8000/ >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then
    open http://127.0.0.1:8000/ >/dev/null 2>&1 || true
  fi
) &

cd "$BACKEND"
exec "$PY" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
