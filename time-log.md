# WhichAP — Claude Active Development Time

Only tracks time Claude is actively working (reading, editing, building, researching). Does not include user idle time.

## 2026-03-21 — Session 1 (late night)
- Estimated ~2.5 hours active (pre-tracking, estimated from commit gaps)
- Work: PRD review, Phases 1-5 scaffold, diagnostics, copy-to-clipboard, two-line menu bar attempts, signal warning, connection history, time-on-AP, live-updating menu

## 2026-03-21 — Session 2 (afternoon)
- Estimated ~1.5 hours active
- Work: Performance/security audit, 10 optimizations, .dmg packaging, manual BSSID entry UI, format hints, BSSID pre-fill, dedup fix, about text update, version bumps

## 2026-03-21–25 — Session 3 (multi-day)
- Estimated ~2 hours active
- Work: Click-to-copy dropdown items, "AP Name:" prefix, "Copy All" rename, app icon from stitch 11, Wi-Fi restart feature, CWEventDelegate monitoring, menu bar cache-clearing fix for Wi-Fi toggle recovery, Wi-Fi Settings link, mapping editor (all entries with search/filter/edit), Help window, copyright in About, show band removal, README updates, license discussion, code signing research

## 2026-04-14–16 — Session 4 (multi-day)
- Estimated ~4 hours active
- Work: Diagnosed Self Service location-permission bug (coworkers saw "No Wi-Fi" with no prompt). Verified Apple PPPC docs — Location Services NOT in PPPC payload, cannot be pre-granted via MDM. Discovered Location Services managed by locationd daemon, NOT TCC — tccutil is a no-op. Added `LocationAccess` enum with `.systemDisabled` state, intro panel, distinct menu states for denied/notDetermined/systemDisabled. Removed broken tccutil button. Wrote Jamf post-install script to pre-authorize via `/var/db/locationd/clients.plist`. Fixed Jamf API script upload bug (newlines stripped by shell XML escaping — must use python3 ET + --data-binary). Fixed auto-launch in post-install (su + stat -f%Su /dev/console). Multiple Jamf deploy/test cycles (1.7.1→1.7.2→1.7.3). Fixed security-scoped bookmark bug (CSV/JSON file mapping lost after reboot — App Sandbox revokes plain path access). CPU optimization: added change tracking to all NSMenuItem property sets in updateMenu (was causing 52% CPU in NSStatusItem _updateReplicants). UX fix: location header text non-red, action buttons blue. Bumped to 1.8.0 (build 16). README, Help window updated throughout.

**Running total: ~10 hours active Claude time**
