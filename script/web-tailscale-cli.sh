#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
[[ -f "$REPO_DIR/.env" ]] && set -a && source "$REPO_DIR/.env" && set +a

# Run the *installed* opencode CLI web server over Tailscale.
# No TLS (installed CLI doesn't support it), but traffic is
# encrypted at the WireGuard layer within the tailnet.

if ! command -v tailscale &>/dev/null; then
  echo "Error: tailscale is not installed or not in PATH" >&2
  exit 1
fi

if ! command -v opencode &>/dev/null; then
  echo "Error: opencode CLI is not installed or not in PATH" >&2
  exit 1
fi

TS_IP=$(tailscale ip -4 2>/dev/null) || true
if [[ -z "$TS_IP" ]]; then
  echo "Error: could not get Tailscale IPv4 address. Is Tailscale running?" >&2
  exit 1
fi

TS_DNS=$(tailscale status --self --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))" 2>/dev/null) || true

if [[ -z "${OPENCODE_SERVER_PASSWORD:-}" ]]; then
  echo "Warning: OPENCODE_SERVER_PASSWORD is not set."
  echo "         The server will be unsecured on your tailnet."
  echo "         Set it with: export OPENCODE_SERVER_PASSWORD=<password>"
  echo ""
fi

CORS_ARGS=(--cors "https://app.opencode.ai")
CORS_ARGS+=(--cors "http://${TS_IP}:4097")
if [[ -n "$TS_DNS" ]]; then
  CORS_ARGS+=(--cors "http://${TS_DNS}:4097")
fi

echo "Starting opencode (installed CLI) on Tailscale IP: $TS_IP"
if [[ -n "$TS_DNS" ]]; then
  echo "MagicDNS: http://$TS_DNS:4097"
fi
echo "Also accessible from: https://app.opencode.ai (add server URL above)"
echo ""

exec opencode web \
  --hostname 0.0.0.0 \
  --port 4097 \
  "${CORS_ARGS[@]}" \
  "$@"
