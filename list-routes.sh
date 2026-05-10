#!/usr/bin/env bash
# Usage: ./list-routes.sh

set -euo pipefail

ACCOUNT_ID="15bfe332876061d9a548a4f3d6835657"
TUNNEL_ID="3e3ddd46-93d1-4c68-bbaf-e04085c1bede"
API="https://api.cloudflare.com/client/v4"
TOKEN="${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN env var}"

curl -sf "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import json, sys
rules = json.load(sys.stdin)['result']['config']['ingress']
for r in rules:
    if r.get('hostname'):
        print(f\"{r['hostname']} -> {r['service']}\")
"
