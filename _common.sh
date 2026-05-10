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

CF_CONFIG="${HOME}/.cloudflared/config.yml"
if [ ! -f "$CF_CONFIG" ]; then
  echo "ERROR: ~/.cloudflared/config.yml not found. Run 'cloudflared tunnel login' first." >&2
  exit 1
fi

# Read credentials file path from config.yml
CREDS_FILE=$(python3 -c "
import sys
for line in open('${CF_CONFIG}'):
    if line.strip().startswith('credentials-file'):
        print(line.split(':', 1)[1].strip())
        break
")

if [ -z "$CREDS_FILE" ] || [ ! -f "$CREDS_FILE" ]; then
  echo "ERROR: credentials-file not found in ${CF_CONFIG}." >&2
  exit 1
fi

# Read ACCOUNT_ID and TUNNEL_ID from credentials JSON
ACCOUNT_ID=$(python3 -c "import json; d=json.load(open('${CREDS_FILE}')); print(d['AccountTag'])")
TUNNEL_ID=$(python3 -c "import json; d=json.load(open('${CREDS_FILE}')); print(d['TunnelID'])")
TUNNEL_NAME=$(python3 -c "
import sys
for line in open('${CF_CONFIG}'):
    line = line.strip()
    if line.startswith('tunnel:'):
        print(line.split(':', 1)[1].strip())
        break
")

API="https://api.cloudflare.com/client/v4"
