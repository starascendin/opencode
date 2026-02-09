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

TS_DNS=$(tailscale status --self --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))" 2>/dev/null) || true

# Warn if no password is set — the server will be network-accessible.
if [[ -z "${OPENCODE_SERVER_PASSWORD:-}" ]]; then
  echo "Warning: OPENCODE_SERVER_PASSWORD is not set."
  echo "         The server will be unsecured on your tailnet."
  echo "         Set it with: export OPENCODE_SERVER_PASSWORD=<password>"
  echo ""
fi

echo "Starting opencode web on Tailscale IP: $TS_IP"
if [[ -n "$TS_DNS" ]]; then
  echo "MagicDNS: https://$TS_DNS"
  echo "Detected MagicDNS name: $TS_DNS"
  echo "MagicDNS: https://$TS_DNS"
fi
echo ""

CORS_ARGS=(--cors "http://${TS_IP}:4096")
if [[ -n "$TS_DNS" ]]; then
  CORS_ARGS+=(--cors "https://${TS_DNS}")
fi

exec opencode web \
  --hostname 0.0.0.0 \
  --port 4096 \
  "${CORS_ARGS[@]}" \
  "$@"
