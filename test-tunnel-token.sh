#!/usr/bin/env bash
# Validation script: does the current CLOUDFLARE_API_TOKEN have enough scope
# to fetch a tunnel install token via the API?
#
# Walks through the same calls get-tunnel-token.sh makes and prints each step's
# outcome, so it's easy to see which permission (if any) is missing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  set -a; source "${SCRIPT_DIR}/.env"; set +a
fi

TOKEN="${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN in env or .env file}"
API="https://api.cloudflare.com/client/v4"

echo "=== 1. Verify the token itself ==="
verify=$(curl -s "${API}/user/tokens/verify" -H "Authorization: Bearer ${TOKEN}")
echo "$verify" | python3 -m json.tool
echo "$verify" | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" || { echo "FAIL: token invalid"; exit 1; }
echo

echo "=== 2. List accounts (GET /accounts) ==="
accounts=$(curl -s "${API}/accounts" -H "Authorization: Bearer ${TOKEN}")
account_count=$(echo "$accounts" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not data.get('success'):
    print(-1); sys.exit(0)
print(len(data.get('result') or []))
")
case "$account_count" in
  -1) echo "  GET /accounts rejected:"; echo "$accounts" | python3 -m json.tool ;;
  0)  echo "  GET /accounts returned success but 0 accounts (token has resource-scoped permissions, not Account:Read)." ;;
  *)  echo "$accounts" | python3 -c "
import json, sys
for a in json.load(sys.stdin).get('result', []):
    print(f\"  {a['id']}  {a['name']}\")
" ;;
esac

if [ "$account_count" = "1" ]; then
  ACCOUNT_ID=$(echo "$accounts" | python3 -c "import json,sys; print(json.load(sys.stdin)['result'][0]['id'])")
else
  ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
  if [ -z "$ACCOUNT_ID" ]; then
    echo "  Need CLOUDFLARE_ACCOUNT_ID in .env. Try: $(ls ~/.cloudflared/*.json 2>/dev/null | head -1)"
    echo "  (the AccountTag field in any existing tunnel credentials JSON is the account ID)"
    exit 1
  fi
  echo "  Using CLOUDFLARE_ACCOUNT_ID=${ACCOUNT_ID} from env"
fi
echo

echo "=== 3. List tunnels (GET /accounts/${ACCOUNT_ID}/cfd_tunnel) ==="
tunnels=$(curl -s "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel?is_deleted=false" -H "Authorization: Bearer ${TOKEN}")
if ! echo "$tunnels" | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin).get('success') else 1)"; then
  echo "FAIL: tunnel listing rejected"
  echo "$tunnels" | python3 -m json.tool
  exit 1
fi
echo "$tunnels" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data.get('result', []):
    if not t.get('deleted_at'):
        print(f\"  {t['id']}  {t['name']}\")
"
TUNNEL_ID=$(echo "$tunnels" | python3 -c "
import json, sys
r = [t for t in json.load(sys.stdin).get('result', []) if not t.get('deleted_at')]
print(r[0]['id'] if r else '')
")
if [ -z "$TUNNEL_ID" ]; then
  echo "FAIL: no tunnels to test against."
  exit 1
fi
echo "Using tunnel: ${TUNNEL_ID}"
echo

echo "=== 4. Fetch tunnel install token (GET /accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token) ==="
token_resp=$(curl -s "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token" -H "Authorization: Bearer ${TOKEN}")
if ! echo "$token_resp" | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin).get('success') else 1)"; then
  echo "FAIL: tunnel token fetch rejected"
  echo "$token_resp" | python3 -m json.tool
  exit 1
fi

TUNNEL_TOKEN=$(echo "$token_resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['result'])")

echo "SUCCESS — tunnel install token:"
echo
echo "${TUNNEL_TOKEN}"
