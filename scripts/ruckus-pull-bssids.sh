#!/bin/bash
# Pull all currently-broadcasting BSSIDs from RUCKUS One via API and write a
# fresh whichap-mapping.json (overwriting the previous one after backing it up).
# Also writes a CSV alongside for human review.
#
# Reads OAuth credentials from macOS Keychain (account=ruckus-claude-code,
# service=ruckus-api). Stored as a JSON blob with client_id, client_secret,
# tenant_id, region, oauth_host, api_host.
#
# Usage:  ./scripts/ruckus-pull-bssids.sh
# Output: whichap-mapping.json (overwritten)
#         data/ruckus-bssids-YYYYMMDD-HHMMSS.csv (timestamped reference)
#         data/whichap-mapping-prev-YYYYMMDD-HHMMSS.json (backup of prior mapping)
set -e
cd "$(dirname "$0")/.."

CREDS=$(security find-generic-password -a "ruckus-claude-code" -s "ruckus-api" -w 2>/dev/null) || {
  echo "✗ No Ruckus credentials in keychain (account=ruckus-claude-code, service=ruckus-api)" >&2
  exit 1
}

CLIENT_ID=$(echo "$CREDS"   | python3 -c "import sys,json;print(json.load(sys.stdin)['client_id'])")
SECRET=$(echo "$CREDS"      | python3 -c "import sys,json;print(json.load(sys.stdin)['client_secret'])")
TENANT_ID=$(echo "$CREDS"   | python3 -c "import sys,json;print(json.load(sys.stdin)['tenant_id'])")
OAUTH_HOST=$(echo "$CREDS"  | python3 -c "import sys,json;print(json.load(sys.stdin)['oauth_host'])")
API_HOST=$(echo "$CREDS"    | python3 -c "import sys,json;print(json.load(sys.stdin)['api_host'])")

echo "→ Authenticating against $OAUTH_HOST..."
TOKEN=$(curl -sk -m 10 -X POST "https://${OAUTH_HOST}/oauth2/token/${TENANT_ID}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "client_secret=$SECRET" \
  --data-urlencode "grant_type=client_credentials" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))")

if [ -z "$TOKEN" ]; then
  echo "✗ OAuth failed" >&2
  exit 1
fi

echo "→ Fetching APs with operational data..."
curl -sk -m 30 -X POST "https://${API_HOST}/aps/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"pageSize": 200}' \
  -o /tmp/ruckus_aps_raw.json

mkdir -p data
TS=$(date +%Y%m%d-%H%M%S)

# Back up existing mapping if present
if [ -f whichap-mapping.json ]; then
  cp whichap-mapping.json "data/whichap-mapping-prev-${TS}.json"
  echo "→ Backed up prior mapping to data/whichap-mapping-prev-${TS}.json"
fi

CSV_OUT="data/ruckus-bssids-${TS}.csv"
WFE_OUT="data/wifi-explorer-annotations-${TS}.csv"
MAP_OUT="whichap-mapping.json"

python3 <<PYEOF
import json
d = json.load(open('/tmp/ruckus_aps_raw.json'))
aps = d.get('data', [])

rows = []
for ap in aps:
    name = ap.get('name', '?')
    apmac = ap.get('apMac', '?')
    for r in ap.get('apStatusData', {}).get('APRadio') or []:
        band = r.get('band', '?')
        ch = r.get('channel', '?')
        for w in r.get('wlans') or []:
            rows.append({
                'apName': name,
                'apMac': apmac,
                'band': band,
                'channel': ch,
                'bssid': (w.get('bssid', '') or '').upper(),
                'ssid': w.get('WlanName', '?'),
            })

# Sort by AP name (case-insensitive), then by BSSID for stable order within each AP
rows.sort(key=lambda r: (r['apName'].lower(), r['bssid']))

# Detailed CSV (for human review and other tools)
with open("$CSV_OUT", 'w') as f:
    f.write("apName,apMac,band,channel,bssid,ssid\n")
    for r in rows:
        f.write(f'"{r["apName"]}","{r["apMac"]}","{r["band"]}",{r["channel"]},{r["bssid"]},"{r["ssid"]}"\n')

# Wi-Fi Explorer annotations CSV (BSSID,Name) — full AP name including IT suffix
with open("$WFE_OUT", 'w') as f:
    f.write("BSSID,Name\n")
    for r in rows:
        # Quote names that contain commas to keep CSV well-formed
        name = r["apName"]
        if "," in name or '"' in name:
            name = '"' + name.replace('"', '""') + '"'
        f.write(f'{r["bssid"]},{name}\n')

# whichap-mapping.json (Data-Studio-shaped so the existing parser handles it)
mapping = {
    "result": [
        {
            "data": [{"apName": r["apName"], "bssid": r["bssid"]} for r in rows],
            "colnames": ["apName", "bssid"],
            "coltypes": [1, 1],
        },
        {
            "data": [{"rowcount": len(rows)}],
            "colnames": ["rowcount"],
            "coltypes": [0],
        },
    ]
}
with open("$MAP_OUT", 'w') as f:
    json.dump(mapping, f, indent=2)

print(f"→ Wrote {len(rows)} BSSIDs across {len(aps)} APs")
print(f"   - $MAP_OUT (overwritten — drop-in replacement for WhichAP)")
print(f"   - $CSV_OUT (detailed CSV for review)")
print(f"   - $WFE_OUT (BSSID,Name — import into Wi-Fi Explorer)")
PYEOF

rm -f /tmp/ruckus_aps_raw.json
echo "✓ Done."
