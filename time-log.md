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

## 2026-04-28 — Session 7
- 20:36 EDT through 00:40 EDT (next day) — extended evening session, ~3.5 hours active
- Phase 1 (20:36–21:55): 1.9.0 ship pipeline. Ran 5-min CPU test on Build 22 (0.0% sustained, 13 MB stable). Verified pre-1.9.0 Codable migration with 137 stripped events. Confirmed real-world Sticky + Ping-pong flag firing in Jason's history. Updated README + .gitignore (Building-and-Deploying / Jamf-Onboarding-Audit docs ignored). Committed 1.9.0 (13 files, +1098/-141), tagged v1.9.0, pushed. Clean Release rebuild. Built/notarized/stapled both DMGs (public + Granger) and Granger pkg. Created GitHub release v1.9.0. Initially mis-applied "staged rollout" plan from memory; Jason course-corrected to in-place pattern. PUT package 314 → 1.9.0 metadata, PUT smart group 301 → renamed + criterion bumped to 1.9.0. Saved feedback memory `feedback_default_to_established_pattern.md`.
- Phase 2 (22:00–22:50): **Pkg deploy failure + recovery.** Pkg I built had wrong payload layout (`./WhichAP.app` instead of `./Applications/WhichAP.app`); Jamf install failed at 22:05 with "system volume" error AFTER pre-install removed /Applications/WhichAP.app from jpowell2051 (and likely rcarter, dmoore). Disabled policy 204 to stop bleeding. Rebuilt pkg with correct `Applications/` parent layout via `pkgbuild --analyze`. Test-installed locally on jpowell2051 (verified 1.9.0 in /Applications). Computed SHA-512 and PUT to package 314 hash field. Saved feedback memory `feedback_test_install_pkg_locally.md`.
- Phase 3 (22:42–23:30): One-Mac canary verification before re-enabling fleet-wide. Saved policy 204 snapshot, narrowed scope to computer 564 only, ran `sudo jamf policy -id 204` (Terminal App Management notification — install proceeded anyway via BundleOverwriteAction=upgrade). Verified end-to-end Jamf flow: download from CasperShare, hash verify, install, post-install + Recon. Restored policy 204 scope to group 299 fleet-wide. Re-armed 20-min rollout poll. Watched smart group 301 grow from 0 → 3 (jpowell, dmoore, rcarter) by 23:13.
- Phase 4 (23:30–00:40): Hardening pass. Drafted improvement-roadmap doc and saved at `docs/improvement-roadmap.md`. Designed and implemented three structural artifacts to prevent recurrence of the pkg-layout failure: `CLAUDE.md` at repo root (project rules + reference info, broader scope per Jason), `docs/release-checklist.md` (ship procedure with semver criteria + 🔴 GATE markers), and `scripts/build-pkg.sh` (parameterized public-dmg/granger-dmg/granger-pkg builder with structural gates: payload layout, mapping size privacy gate, codesign + entitlements verify, PackageInfo bundle path verify). Caught and fixed two SIGPIPE bugs in script (grep -q + head/tail with `set -o pipefail` → captured-then-process pattern). Verified script reproduces deployed pkg structurally (payload + PackageInfo identical, only timestamp metadata differs).

**Running total: ~20.5 hours active Claude time**
