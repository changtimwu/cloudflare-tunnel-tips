#!/usr/bin/env bash
# Usage: ./list-routes.sh

set -euo pipefail
source "$(dirname "$0")/_common.sh"

curl -sf "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import json, sys
rules = json.load(sys.stdin)['result']['config']['ingress']
for r in rules:
    if r.get('hostname'):
        print(f\"{r['hostname']} -> {r['service']}\")
"
