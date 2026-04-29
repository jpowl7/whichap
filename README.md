# WhichAP

A lightweight macOS menu bar utility that shows which Wi-Fi access point you're connected to.

Instead of a raw BSSID (MAC address), WhichAP displays a friendly AP name like `TechOps - AC43` right in the menu bar — alongside your SSID. You provide a mapping of BSSIDs to AP names via JSON, CSV, a hosted URL, or manual entry.

## Features

- **Two-line menu bar display** — SSID on top, AP name below
- **Geek mode** — optional display showing SSID:AP Name on top, signal%|band|channel on bottom
- **AP manufacturer lookup** — identifies the AP vendor via the IEEE OUI database (cached in memory)
- **Detailed connection info dropdown** — signal strength, noise, SNR, band, channel, PHY mode, Tx rate, IP address, security type, manufacturer
- **Signal quality warning** — menu bar and dropdown text turns red when signal is Poor or Bad
- **Signal % style** — choose between Standard (conservative, clamped at -37 dBm) and Lenient (linear -50 → -100 dBm) in Preferences
- **Connection timer** — shows how long you've been on the current AP (live-updating)
- **Mac uptime** — shows system uptime in the dropdown (days, hours, minutes), read from `kern.boottime` so it matches Terminal `uptime`
- **Connection history (up to 1,000 events)** — logs every AP hop, reconnect, and channel change with timestamp. Columns include Type, Duration, signal at moment of leaving, channel, BSSID, and a problem flag. Filter the view to All / Roams only / Problems only. Persists across restarts.
- **Roam pattern flags** — automatically marks Sticky (held a weak AP too long), Ping-pong (rapid flapping between two APs), and Slow-roam (long delay before joining a new AP) events
- **Channel-change detection** — records a separate event when an AP changes channel without a BSSID change
- **Roam notifications (opt-in)** — optional macOS notifications when you roam, reconnect, or an AP changes channel. Choose All events or Problems only. Off by default.
- **Click to copy** — click any item in the dropdown to copy its value. "Copy All" formats everything for a support ticket.
- **Restart Wi-Fi** — one-click Wi-Fi toggle from the dropdown, auto-recovers
- **Wi-Fi Settings** — quick link to macOS Wi-Fi settings
- **Mapping editor** — view all BSSID mappings (bundled, file, manual) with search/filter. Edit or remove manual/file entries inline.
- **Manual BSSID entry** — add AP names one at a time in Preferences, auto-fills current BSSID
- **Multiple mapping sources** — bundled JSON, local file import (JSON/CSV), or remote URL with auto-refresh (hourly/daily/weekly)
- **Truncate AP name at colon** — optional preference to hide technical suffix from AP names
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

The app is signed with a Developer ID certificate and notarized with Apple — no Gatekeeper warnings.

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
- **Preferences > View & Edit Mappings** — browse all mappings (bundled, file, manual) with search, edit or remove entries inline

## Location Services

WhichAP requires Location Services permission to read the BSSID from CoreWLAN. This is an Apple requirement — the app does **not** track or store your location.

On first launch, WhichAP shows a brief intro panel explaining what's about to happen, then triggers the macOS permission prompt. Click **Allow**.

### If the prompt never appeared

If the menu bar says **"⚠ Location Off"** even when you're connected to Wi-Fi, click the WhichAP menu. You'll see one of three states:

- **"Location Services Disabled"** — the system-wide Location Services switch is off. Click **Open Location Settings…** and turn on the master switch at the top.
- **"Location Access Required"** — WhichAP is in the list but toggled off. Click **Open Location Settings…** and toggle WhichAP on.
- **"Location Permission Needed"** — the macOS prompt hasn't been shown yet. Click **Grant Location Access…** to trigger it.

### IT admins (Jamf / MDM)

Location Services **cannot** be pre-granted via MDM configuration profiles — Apple intentionally requires user consent for location access ([PPPC payload reference](https://support.apple.com/guide/deployment/privacy-preferences-policy-control-payload-dep38df53c2a/web)). However, a Jamf post-install script can pre-authorize the app by writing to `/var/db/locationd/clients.plist`. See the Jamf deployment notes for the script.

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel (universal binary)

## License

Copyright 2026 Jason Powell. All rights reserved.
