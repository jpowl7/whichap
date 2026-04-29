#!/bin/bash
# Pull a fresh list of all APs from RUCKUS One via API.
# Reads OAuth credentials from macOS Keychain (account=ruckus-claude-code,
# service=ruckus-api). Stored as a JSON blob with client_id, client_secret,
# tenant_id, region, oauth_host, api_host.
#
# Usage:  ./scripts/ruckus-pull-aps.sh                  # pretty table to stdout
#         ./scripts/ruckus-pull-aps.sh > aps.json       # raw JSON
set -e

CREDS=$(security find-generic-password -a "ruckus-claude-code" -s "ruckus-api" -w 2>/dev/null) || {
  echo "✗ No Ruckus credentials in keychain (account=ruckus-claude-code, service=ruckus-api)" >&2
  exit 1
}

CLIENT_ID=$(echo "$CREDS"   | python3 -c "import sys,json;print(json.load(sys.stdin)['client_id'])")
SECRET=$(echo "$CREDS"      | python3 -c "import sys,json;print(json.load(sys.stdin)['client_secret'])")
TENANT_ID=$(echo "$CREDS"   | python3 -c "import sys,json;print(json.load(sys.stdin)['tenant_id'])")
OAUTH_HOST=$(echo "$CREDS"  | python3 -c "import sys,json;print(json.load(sys.stdin)['oauth_host'])")
API_HOST=$(echo "$CREDS"    | python3 -c "import sys,json;print(json.load(sys.stdin)['api_host'])")

TOKEN=$(curl -sk -m 10 -X POST "https://${OAUTH_HOST}/oauth2/token/${TENANT_ID}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "client_secret=$SECRET" \
  --data-urlencode "grant_type=client_credentials" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))")

if [ -z "$TOKEN" ]; then
  echo "✗ OAuth failed — check credentials" >&2
  exit 1
fi

# If stdout is a terminal, print a table. Otherwise dump raw JSON.
if [ -t 1 ]; then
  curl -sk -m 30 "https://${API_HOST}/venues/aps" \
    -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
    | python3 -c "
import json, sys
aps = json.load(sys.stdin)
print(f'{len(aps)} APs from RUCKUS One')
print()
print(f'{\"AP Name\":<45}  {\"Primary MAC\":<18}  {\"Serial\":<14}  {\"State\":<12}  {\"Model\":<8}')
print('-' * 110)
for ap in sorted(aps, key=lambda a: (a.get('name','') or '').lower()):
    print(f'{(ap.get(\"name\") or \"?\")[:45]:<45}  {ap.get(\"mac\",\"?\"):<18}  {ap.get(\"serialNumber\",\"?\"):<14}  {ap.get(\"state\",\"?\"):<12}  {ap.get(\"model\",\"?\"):<8}')
"
else
  curl -sk -m 30 "https://${API_HOST}/venues/aps" \
    -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
fi
