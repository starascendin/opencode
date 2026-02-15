#!/usr/bin/env bash
set -euo pipefail

# OpenCode Tauri Remote — connects to VPS via Tailscale
# Usage: ./script/tauri-remote.sh

REMOTE_URL="https://vps-60d9e960.tail05d28.ts.net:4096/"
PORT=19476

cd "$(dirname "$0")/.."

# Kill stale processes on our port
lsof -ti:$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true

echo "Starting OpenCode Remote → $REMOTE_URL (port $PORT)"

OPENCODE_REMOTE_URL="$REMOTE_URL" \
  bun --cwd packages/desktop tauri dev \
  --config "{\"identifier\":\"ai.opencode.desktop.remote\",\"productName\":\"OpenCode Remote\",\"build\":{\"devUrl\":\"http://localhost:$PORT\",\"beforeDevCommand\":\"bunx vite --port $PORT\"}}"
