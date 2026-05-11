#!/usr/bin/env bash
# Usage: ./remove-route.sh <subdomain>
# Example: ./remove-route.sh mymbpr-demo

set -euo pipefail
source "$(dirname "$0")/_common.sh"

SUBDOMAIN="${1:?Usage: $0 <subdomain>}"
HOSTNAME="${SUBDOMAIN}.${DOMAIN}"

ZONE_ID=$(curl -sf "${API}/zones?name=${DOMAIN}" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result'][0]['id'])")

echo "Fetching current tunnel config..."
current=$(curl -s "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${TOKEN}")

existing=$(echo "$current" | python3 -c "
import json, sys
rules = (json.load(sys.stdin).get('result') or {}).get('config', {}).get('ingress', [])
rules = [r for r in rules if r.get('service') != 'http_status:404']
print(json.dumps(rules))
")

if ! echo "$existing" | grep -q "\"${HOSTNAME}\""; then
  echo "ERROR: ${HOSTNAME} not found in tunnel config."
  exit 1
fi

new_config=$(python3 -c "
import json
rules = json.loads('${existing}')
rules = [r for r in rules if r.get('hostname') != '${HOSTNAME}']
rules.append({'service': 'http_status:404'})
print(json.dumps({'config': {'ingress': rules}}))
")

echo "Pushing updated config (removing ${HOSTNAME})..."
result=$(curl -sf -X PUT "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$new_config")

if ! echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('success') else 1)"; then
  echo "ERROR: API call failed:"
  echo "$result" | python3 -m json.tool
  exit 1
fi

echo "Removing DNS CNAME..."
record_id=$(curl -sf "${API}/zones/${ZONE_ID}/dns_records?name=${HOSTNAME}&type=CNAME" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import json, sys
results = json.load(sys.stdin).get('result', [])
print(results[0]['id'] if results else '')
")

if [ -n "$record_id" ]; then
  curl -sf -X DELETE "${API}/zones/${ZONE_ID}/dns_records/${record_id}" \
    -H "Authorization: Bearer ${TOKEN}" > /dev/null
  echo "DNS CNAME removed."
else
  echo "No DNS CNAME found for ${HOSTNAME} (may have already been removed)."
fi

echo ""
echo "Done! ${HOSTNAME} has been removed."
