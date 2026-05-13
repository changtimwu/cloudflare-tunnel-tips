#!/usr/bin/env bash
# Usage: ./get-tunnel-token.sh <tunnel-name>
#
# Fetches the install token for a Cloudflare Tunnel via the API.
# Creates the tunnel if it doesn't exist (with a random secret, remotely-managed).
# Prints the token to stdout — pipe it into `sudo cloudflared service install`.
#
# Example:
#   sudo cloudflared service install "$(./get-tunnel-token.sh mymbpr)"
#
# Required env: CLOUDFLARE_API_TOKEN (also loaded from .env beside this script)
# Optional env: CLOUDFLARE_ACCOUNT_ID (skip account auto-discovery)

set -euo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  [[ "$_src" != /* ]] && _src="${_dir}/${_src}"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
if [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  set -a; source "${SCRIPT_DIR}/.env"; set +a
fi

TOKEN="${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN in env or .env file}"
TUNNEL_NAME="${1:?Usage: $0 <tunnel-name>}"

API="https://api.cloudflare.com/client/v4"

# Discover account ID via API if not provided
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
if [ -z "$ACCOUNT_ID" ]; then
  ACCOUNT_ID=$(curl -s "${API}/accounts" -H "Authorization: Bearer ${TOKEN}" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not data.get('success'):
    errs = data.get('errors', [])
    print(f'ERROR: account lookup failed: {errs}', file=sys.stderr)
    print('Hint: set CLOUDFLARE_ACCOUNT_ID in .env if your token lacks Account:Read.', file=sys.stderr)
    sys.exit(1)
accs = data.get('result') or []
if len(accs) == 0:
    print('ERROR: token has no Account:Read permission (returned 0 accounts).', file=sys.stderr)
    print('Hint: set CLOUDFLARE_ACCOUNT_ID in .env — read it from any ~/.cloudflared/*.json (AccountTag).', file=sys.stderr)
    sys.exit(1)
if len(accs) > 1:
    print(f'ERROR: {len(accs)} accounts visible — set CLOUDFLARE_ACCOUNT_ID to one of:', file=sys.stderr)
    for a in accs:
        print(f'  {a[\"id\"]}  ({a[\"name\"]})', file=sys.stderr)
    sys.exit(1)
print(accs[0]['id'])
")
fi

echo "Account: ${ACCOUNT_ID}" >&2

# Look up tunnel by name (filtered to non-deleted)
TUNNEL_ID=$(curl -s "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel?name=${TUNNEL_NAME}&is_deleted=false" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not data.get('success'):
    print(f'ERROR: tunnel lookup failed: {data.get(\"errors\")}', file=sys.stderr)
    sys.exit(1)
match = [t for t in (data.get('result') or []) if t.get('name') == '${TUNNEL_NAME}' and not t.get('deleted_at')]
print(match[0]['id'] if match else '')
")

if [ -z "$TUNNEL_ID" ]; then
  echo "Tunnel '${TUNNEL_NAME}' not found — creating a new one..." >&2
  TUNNEL_SECRET=$(python3 -c "import os, base64; print(base64.b64encode(os.urandom(32)).decode())")
  CREATE_BODY=$(python3 -c "
import json, sys
print(json.dumps({'name': sys.argv[1], 'tunnel_secret': sys.argv[2], 'config_src': 'cloudflare'}))
" "$TUNNEL_NAME" "$TUNNEL_SECRET")
  TUNNEL_ID=$(curl -s -X POST "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$CREATE_BODY" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not data.get('success'):
    print(f'ERROR: tunnel creation failed: {data.get(\"errors\")}', file=sys.stderr)
    sys.exit(1)
print(data['result']['id'])
")
  echo "Created tunnel: ${TUNNEL_ID}" >&2
else
  echo "Found tunnel: ${TUNNEL_ID}" >&2
fi

# Fetch the install token
curl -s "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not data.get('success'):
    print(f'ERROR: token fetch failed: {data.get(\"errors\")}', file=sys.stderr)
    sys.exit(1)
print(data['result'])
"
