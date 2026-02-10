#!/usr/bin/env bash
set -euo pipefail

# Run opencode web with Tailscale HTTPS via MagicDNS.
# Uses Tailscale-provisioned TLS certs for native HTTPS.

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

# Locate/generate TLS certs in a user-writable path.
CERT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode/tailscale-certs"
TLS_ARGS=()
if [[ -n "$TS_DNS" ]]; then
  mkdir -p "$CERT_DIR"
  CERT_FILE="$CERT_DIR/$TS_DNS.crt"
  KEY_FILE="$CERT_DIR/$TS_DNS.key"
  if [[ ! -s "$CERT_FILE" || ! -s "$KEY_FILE" ]]; then
    tailscale cert --cert-file "$CERT_FILE" --key-file "$KEY_FILE" "$TS_DNS" >/dev/null 2>&1 || true
  fi
  if [[ -s "$CERT_FILE" && -s "$KEY_FILE" ]]; then
    TLS_ARGS=(--tls-cert "$CERT_FILE" --tls-key "$KEY_FILE")
  else
    echo "Warning: TLS certs unavailable for $TS_DNS."
    echo "         Run: tailscale cert --cert-file $CERT_FILE --key-file $KEY_FILE $TS_DNS"
    echo "         Falling back to HTTP."
    echo ""
  fi
fi

# Warn if no password is set — the server will be network-accessible.
if [[ -z "${OPENCODE_SERVER_PASSWORD:-}" ]]; then
  echo "Warning: OPENCODE_SERVER_PASSWORD is not set."
  echo "         The server will be unsecured on your tailnet."
  echo "         Set it with: export OPENCODE_SERVER_PASSWORD=<password>"
  echo ""
fi

CORS_ARGS=(--cors "http://${TS_IP}:4096")
if [[ -n "$TS_DNS" ]]; then
  CORS_ARGS+=(--cors "https://${TS_DNS}")
  CORS_ARGS+=(--cors "https://${TS_DNS}:4096")
fi

echo "Starting opencode web on Tailscale IP: $TS_IP"
if [[ -n "$TS_DNS" ]]; then
  if [[ ${#TLS_ARGS[@]} -gt 0 ]]; then
    echo "HTTPS: https://$TS_DNS:4096"
  else
    echo "MagicDNS: http://$TS_DNS:4096"
  fi
fi
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$REPO_DIR/packages/app"
WEB_DIR="$APP_DIR/dist"

# Determine server URL for the build
if [[ ${#TLS_ARGS[@]} -gt 0 && -n "$TS_DNS" ]]; then
  SERVER_URL="https://${TS_DNS}:4096"
else
  SERVER_URL="http://${TS_IP}:4096"
fi

# Build the web app locally
echo "Building web app..."
VITE_OPENCODE_SERVER_URL="$SERVER_URL" bun --cwd "$APP_DIR" build
echo "Web app built."
echo ""

export OPENCODE_WEB_DIR="$WEB_DIR"

exec bun run --cwd "$REPO_DIR/packages/opencode" --conditions=browser src/index.ts web \
  --hostname 0.0.0.0 \
  --port 4096 \
  "${CORS_ARGS[@]}" \
  "${TLS_ARGS[@]}" \
  "$@"
