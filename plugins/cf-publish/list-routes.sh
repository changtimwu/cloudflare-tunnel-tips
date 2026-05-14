#!/usr/bin/env bash
# Usage: ./list-routes.sh

set -euo pipefail
source "$(dirname "$0")/_common.sh"

curl -s "${API}/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import json, sys
result = json.load(sys.stdin).get('result') or {}
rules = result.get('config', {}).get('ingress', [])
routes = [r for r in rules if r.get('hostname')]
if not routes:
    print('No routes configured.')
else:
    for r in routes:
        print(f\"{r['hostname']} -> {r['service']}\")
"
