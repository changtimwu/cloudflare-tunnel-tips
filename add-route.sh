#!/usr/bin/env bash
# Usage: ./add-route.sh <subdomain> <port>
# Example: ./add-route.sh mymbpr-demo 3000

set -euo pipefail
source "$(dirname "$0")/_common.sh"

SUBDOMAIN="${1:?Usage: $0 <subdomain> <port>}"
PORT="${2:?Usage: $0 <subdomain> <port>}"
HOSTNAME="${SUBDOMAIN}.${DOMAIN}"

echo "Fetching current tunnel config..."
current=$(curl -sf "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${TOKEN}")

existing=$(echo "$current" | python3 -c "
import json, sys
rules = json.load(sys.stdin).get('result', {}).get('config', {}).get('ingress', [])
rules = [r for r in rules if r.get('service') != 'http_status:404']
print(json.dumps(rules))
")

if echo "$existing" | grep -q "\"${HOSTNAME}\""; then
  echo "ERROR: ${HOSTNAME} already exists in tunnel config."
  exit 1
fi

new_config=$(python3 -c "
import json
existing = json.loads('${existing}')
new_rule = {'hostname': '${HOSTNAME}', 'service': 'http://localhost:${PORT}'}
rules = existing + [new_rule, {'service': 'http_status:404'}]
print(json.dumps({'config': {'ingress': rules}}))
")

echo "Pushing new config (adding ${HOSTNAME} → localhost:${PORT})..."
result=$(curl -sf -X PUT "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$new_config")

if ! echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('success') else 1)"; then
  echo "ERROR: API call failed:"
  echo "$result" | python3 -m json.tool
  exit 1
fi

echo "Adding DNS CNAME..."
cloudflared tunnel route dns "${TUNNEL_NAME}" "${HOSTNAME}" 2>/dev/null || true

echo ""
echo "Done! https://${HOSTNAME} → localhost:${PORT}"
