#!/usr/bin/env bash
set -euo pipefail

# Run opencode web bound to the Tailscale interface so it's accessible
# from any device on your tailnet.

if ! command -v tailscale &>/dev/null; then
  echo "Error: tailscale is not installed or not in PATH" >&2
  exit 1
fi

TS_IP=$(tailscale ip -4 2>/dev/null) || true
if [[ -z "$TS_IP" ]]; then
  echo "Error: could not get Tailscale IPv4 address. Is Tailscale running?" >&2
  exit 1
fi

# Warn if no password is set — the server will be network-accessible.
if [[ -z "${OPENCODE_SERVER_PASSWORD:-}" ]]; then
  echo "Warning: OPENCODE_SERVER_PASSWORD is not set."
  echo "         The server will be unsecured on your tailnet."
  echo "         Set it with: export OPENCODE_SERVER_PASSWORD=<password>"
  echo ""
fi

echo "Starting opencode web on Tailscale IP: $TS_IP"
echo ""

exec opencode web \
  --hostname 0.0.0.0 \
  --port 4096 \
  --cors "http://${TS_IP}:4096" \
  "$@"
