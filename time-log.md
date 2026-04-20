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

## 2026-04-16 — Session 4 continued (evening)
- Estimated ~2 hours active
- Work: Fixed NSMenuItem "NSMenuItem" display bug (uptime/connected time not set on first render). Fixed launch-at-login (SMAppService.mainApp.register() never called at launch). Full release pipeline for 1.8.0 and 1.8.1. CPU/memory monitoring (0.0% idle, ~60MB steady). Set up Jamf auto-deploy: Ongoing policy with exclusion Smart Group pattern. Created Jamf API Client + Role, stored credentials in Keychain for automated API access. Read-only audit of all 133 Jamf policies, documented full onboarding flow to Jamf-Onboarding-Audit.md.

## 2026-04-17 — Session 5
- Estimated ~3 hours active
- Work: Fixed manufacturer lookup retry bug (was inside BSSID change guard, never retried on failure). Added signal % ranges to Help window. Fixed location action button color (blue → red per Jason's feedback). Rewrote Jamf post-install script to handle fresh installs (launch app briefly to create locationd entry, then authorize). Set up Jamf API Client with stored Keychain credentials — no more manual token prompts. Automated Jamf package record + exclusion group updates via API. Built/deployed 1.8.2 and 1.8.3 via full pipeline. Deployed to ptarwacki and tzinich via blank push — discovered blank push triggers ALL pending policies (FileVault prompt, Ruckus URL, etc.). Audited all 133 Jamf policies, documented full onboarding flow. **Open issue:** locationd Authorized key doesn't persist after launchctl kickstart on fresh installs — needs debugging.

## 2026-04-19 — Session 6
- Estimated ~2 hours active
- Work: Discovered all Granger/pkg builds since 1.7.0 had entitlements stripped during re-signing (codesign --force without --entitlements). This was the root cause of SMAppService login item failures, location authorization issues, and security-scoped bookmark failures on deployed Macs. Fixed by passing --entitlements during re-sign. Updated entitlements file with all four entries. Also discovered launchctl kickstart for locationd is blocked by SIP on all production Macs. Bumped to 1.8.4, deployed to Jason's Mac — macOS location system prompt appeared correctly for the first time on a Jamf install. **Verified post-reboot:** WhichAP auto-launched into menu bar via SMAppService, showed SSID and AP name, no location re-prompt — TCC grant persisted. End-to-end Jamf deploy + entitlements fix confirmed working.

**Running total: ~17 hours active Claude time**
