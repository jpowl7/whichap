# WhichAP

A lightweight macOS menu bar utility that shows which Wi-Fi access point you're connected to.

Instead of a raw BSSID (MAC address), WhichAP displays a friendly AP name like `TechOps - AC43` right in the menu bar — alongside your SSID. You provide a mapping of BSSIDs to AP names via JSON, CSV, a hosted URL, or manual entry.

## Features

- **Two-line menu bar display** — SSID on top, AP name below
- **Detailed connection info dropdown** — signal strength, noise, SNR, band, channel, PHY mode, Tx rate, IP address, security type
- **Signal quality warning** — menu bar and dropdown text turns red when signal is Poor or Bad
- **Connection timer** — shows how long you've been on the current AP (live-updating)
- **Mac uptime** — shows system uptime in the dropdown (days, hours, minutes)
- **Connection history** — logs every AP hop with timestamp in a searchable table. Persists across restarts.
- **Click to copy** — click any item in the dropdown to copy its value. "Copy All" formats everything for a support ticket.
- **Restart Wi-Fi** — one-click Wi-Fi toggle from the dropdown, auto-recovers
- **Wi-Fi Settings** — quick link to macOS Wi-Fi settings
- **Mapping editor** — view all BSSID mappings (bundled, file, manual) with search/filter. Edit or remove manual/file entries inline.
- **Manual BSSID entry** — add AP names one at a time in Preferences, auto-fills current BSSID
- **Multiple mapping sources** — bundled JSON, local file import (JSON/CSV), or remote URL with auto-refresh (hourly/daily/weekly)
- **Wi-Fi event monitoring** — instant detection of Wi-Fi state changes via CWEventDelegate (no polling delay)
- **Adaptive polling** — 2s when roaming, 10s when stable, 5s when disconnected
- **Launch at login** — via macOS Login Items (SMAppService)
- **Tiny footprint** — ~2 MB, native Swift, no Electron, no dependencies

## Install

### From DMG
1. Open `WhichAP-x.x.x.dmg`
2. Drag **WhichAP** to **Applications**
3. Launch from Applications or Spotlight
4. Click **Allow** on the Location Services prompt (required for BSSID access)

Note: If the app hasn't been notarized with Apple, you may need to right-click > Open > click Open to bypass Gatekeeper on first launch.

### From source
```bash
git clone https://github.com/jpowl7/whichap.git
cd whichap
xcodebuild build -project WhichAP.xcodeproj -scheme WhichAP -configuration Release \
  -destination "platform=macOS" CONFIGURATION_BUILD_DIR=build/Release
open build/Release/WhichAP.app
```

Requires Xcode and macOS 13+.

## Providing Your BSSID Mapping

WhichAP needs a mapping of BSSID (MAC address) to AP name. Without it, the app shows your SSID but can't identify the specific access point.

### Accepted Formats

**JSON — Ruckus Data Studio export:**
```json
{"result":[{"data":[{"apName":"Lobby North","bssid":"00:33:58:A9:B5:F0"}, ...]}]}
```

**JSON — Simple array:**
```json
[{"apName":"Lobby North","bssid":"00:33:58:A9:B5:F0"}, ...]
```

**CSV:**
```csv
apName,bssid
Lobby North,00:33:58:A9:B5:F0
TechOps - AC43,00:33:58:A9:EC:02
```

### How to Load

- **Preferences > Source: File** — import a local .json or .csv file
- **Preferences > Source: URL** — point to a hosted mapping file (e.g., on Vercel) for automatic updates
- **Preferences > Manual Entry** — type in AP name and BSSID one at a time (current BSSID auto-fills)
- **Preferences > View & Edit Mappings** — browse all mappings (bundled + manual) with search, edit manual entries inline, remove manual entries

## Location Services

WhichAP requires Location Services permission to read the BSSID from CoreWLAN. This is an Apple requirement — the app does **not** track or store your location.

On first launch, you'll see: *"WhichAP would like to use your current location"* — click **Allow**.

If denied, the app still works but only shows the SSID (no AP name).

## Jamf Deployment

WhichAP supports managed preferences via the `com.grangerchurch.whichap` domain. Set these keys in a Configuration Profile:

| Key | Type | Values |
|-----|------|--------|
| `mappingSource` | String | `bundled`, `file`, `url` |
| `mappingURL` | String | HTTPS URL to mapping JSON |
| `fetchInterval` | String | `hourly`, `daily`, `weekly` |
| `launchAtLogin` | Boolean | `true` / `false` |

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel (universal binary)

## License

Copyright 2026 Jason Powell. All rights reserved.
