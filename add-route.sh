#!/usr/bin/env bash
# Usage: ./add-route.sh <subdomain> <port>
# Example: ./add-route.sh mymbpr-demo 3000
#
# Adds a new public hostname to the mymbpr tunnel and restarts cloudflared.
# Requires CLOUDFLARE_API_TOKEN env var with "Cloudflare Tunnel: Edit" permission.
# Create one at: https://dash.cloudflare.com/profile/api-tokens

set -euo pipefail

SUBDOMAIN="${1:?Usage: $0 <subdomain> <port>}"
PORT="${2:?Usage: $0 <subdomain> <port>}"

ACCOUNT_ID="15bfe332876061d9a548a4f3d6835657"
TUNNEL_ID="3e3ddd46-93d1-4c68-bbaf-e04085c1bede"
DOMAIN="wormhole.work"
API="https://api.cloudflare.com/client/v4"
TOKEN="${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN env var}"

HOSTNAME="${SUBDOMAIN}.${DOMAIN}"

echo "Fetching current tunnel config..."
current=$(curl -sf "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${TOKEN}")

# Extract existing ingress rules (everything except the catchall http_status:404)
existing=$(echo "$current" | python3 -c "
import json, sys
data = json.load(sys.stdin)
rules = data.get('result', {}).get('config', {}).get('ingress', [])
# Remove catchall
rules = [r for r in rules if r.get('service') != 'http_status:404']
print(json.dumps(rules))
")

# Check if hostname already exists
if echo "$existing" | grep -q "\"${HOSTNAME}\""; then
  echo "ERROR: ${HOSTNAME} already exists in tunnel config."
  exit 1
fi

# Build new config: existing rules + new rule + catchall
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
cloudflared tunnel route dns mymbpr "${HOSTNAME}" 2>/dev/null || true

echo ""
echo "Done! https://${HOSTNAME} → localhost:${PORT}"
echo "The running cloudflared will pick up the new route automatically."
