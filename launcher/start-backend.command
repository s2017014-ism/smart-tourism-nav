#!/usr/bin/env bash
# macOS: double-click to start the backend.
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$DIR/start-backend.sh"
echo
echo "Press any key to close this window..."
read -n 1 -s
