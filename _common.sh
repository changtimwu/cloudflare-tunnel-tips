#!/usr/bin/env bash
# Sourced by add-route.sh / remove-route.sh / list-routes.sh
# Reads tunnel identity from cloudflared's own config files — no hardcoded IDs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load CLOUDFLARE_DOMAIN (and optionally CLOUDFLARE_API_TOKEN) from .env
if [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  set -a; source "${SCRIPT_DIR}/.env"; set +a
fi

TOKEN="${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN in env or .env file}"
DOMAIN="${CLOUDFLARE_DOMAIN:?Set CLOUDFLARE_DOMAIN in .env file (e.g. wormhole.work)}"

if [ ! -f "${HOME}/.cloudflared/cert.pem" ]; then
  echo "ERROR: Not logged in. Run: cloudflared tunnel login" >&2
  exit 1
fi

cred_files=()
for f in "${HOME}/.cloudflared/"*.json; do
  [ -f "$f" ] && cred_files+=("$f")
done

if [ ${#cred_files[@]} -eq 0 ]; then
  echo "ERROR: No tunnel found. Create one first: cloudflared tunnel create <name>" >&2
  exit 1
elif [ ${#cred_files[@]} -gt 1 ]; then
  echo "ERROR: Multiple tunnels found. Set TUNNEL_CREDS_FILE to disambiguate:" >&2
  for f in "${cred_files[@]}"; do
    echo "  $f" >&2
  done
  exit 1
fi

CREDS_FILE="${TUNNEL_CREDS_FILE:-${cred_files[0]}}"

# Read ACCOUNT_ID and TUNNEL_ID from credentials JSON
ACCOUNT_ID=$(python3 -c "import json; d=json.load(open('${CREDS_FILE}')); print(d['AccountTag'])")
TUNNEL_ID=$(python3 -c "import json; d=json.load(open('${CREDS_FILE}')); print(d['TunnelID'])")
TUNNEL_NAME=$(python3 -c "import json; d=json.load(open('${CREDS_FILE}')); print(d.get('TunnelName', d['TunnelID']))")

API="https://api.cloudflare.com/client/v4"
