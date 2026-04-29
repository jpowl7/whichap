# WhichAP — project rules and reference

This file is loaded into every Claude session automatically. Project-specific
rules live here. For ship-time procedure, see `docs/release-checklist.md`.

## Process discipline

- **No guessing.** When uncertain, verify or ask. Don't promote
  researched contingencies to active plans without explicit confirmation.
- **Flag guesses.** Always distinguish "verified" vs "assumed" when
  recommending an action.
- **Ask before modifying shared infrastructure** (Jamf policy/group/package,
  CasperShare, GitHub releases) — even if the user said "go" earlier in
  the session. Authorization stands for the scope specified, not beyond.
- **Verify all artifacts.** Check every location (source, build, DMG,
  pkg, GitHub, Jamf) before reporting "done." File existence is not the
  same as file correctness.
- **Default to parallel** Bash/Agent calls when work is independent.
- **Save open items** to user memory at the end of any session with
  unfinished work.
- **Log active dev time** to `time-log.md` at session start/end.
- **Capture secrets from clipboard via the Bash tool, not `!` prefix.**

## Privacy rules (HARD)

- **Public artifacts must never contain real Granger BSSIDs.** The
  bundled `default-mapping.json` in the public DMG must be the example
  placeholder set (~7 entries, `AA:BB:CC:DD:EE:**` prefix). The Granger
  mapping (`whichap-mapping.json`, ~173 real entries) is for the Granger
  DMG and Granger pkg only.
- **`whichap-mapping.json` stays gitignored.** Never `git add` this
  file.
- **`Building-and-Deploying-via-Jamf.md/.docx` and
  `Jamf-Onboarding-Audit.md/.docx` stay gitignored.** They contain
  Granger's full Jamf policy inventory.
- **Build order:** public artifact first (with bundled example mapping),
  then derive Granger artifact by *copying* the signed app and swapping
  the mapping. Don't reverse the order — easy to leave the Granger
  mapping in the public-bound copy.

## Pkg + Jamf rules

- **Use `scripts/build-pkg.sh` to build any production pkg.** Don't
  invoke `pkgbuild` directly. The script bakes in the `Applications/`
  parent layout and verifies payload structure.
- **Test-install any new pkg locally before Jamf upload:**
  `sudo installer -pkg <pkg> -target /` then verify
  `/Applications/WhichAP.app` exists at the new version. No exceptions.
- **Default Jamf release pattern:** in-place update of package 314 +
  smart group 301 + policy 204. Don't create parallel records unless
  explicitly asked for narrower-than-test-group rollout.
- **Jamf API writes that touch nested elements** (scope, scripts,
  packages): GET the full record, modify in memory via Python
  ElementTree, PUT the full record back. Don't rely on partial-PUT
  field-merge semantics.
- **Jamf script content uploads:** use `python3 ElementTree` +
  `--data-binary @file`, not shell-escaped XML in `--data`. Shell
  escaping eats newlines and breaks scripts on the Jamf side.
- **Never send a Jamf blank push.** Triggers all pending policies on
  the target Mac, including unrelated FileVault prompts and onboarding
  scripts. Hard rule, no exceptions.
- **Verify Jamf config against official docs** (developer.jamf.com,
  support KB) before giving Jamf instructions. Don't recall API
  behavior from training data.
- **One-Mac canary first** for any new policy or significant policy
  change: narrow scope to one Mac, run, verify via `/var/log/jamf.log`,
  then restore scope. Default, not recovery procedure.

## Code signing rules

- **Always pass `--entitlements WhichAP/WhichAP.entitlements`** when
  re-signing for Granger or pkg builds. Without it, all 4 entitlements
  get stripped (the bug fixed in 1.8.4).
- **Hardened runtime + timestamped signature** on every build.
- **Designated Requirement** for the bundle:
  `identifier "com.grangerchurch.whichap" and ... certificate
  leaf[subject.OU] = T6TF2VZNJL`.

## Pre-commit rules

- **Run a 5-minute CPU/memory test on the running build before any
  commit:** `top -l 30 -s 10 -pid $PID -stats pid,cpu,mem,threads,time`.
  Acceptable baseline: ≤0.1% sustained CPU, stable RSS, no thread
  growth.
- **Always `pkill -x WhichAP`** before building/launching a new build
  to avoid stale process state.
- **When adding user-visible features, also update
  `WhichAP/HelpWindow.swift`** to document them. Easy to forget.

## Project context

### Identifiers

- Bundle ID: `com.grangerchurch.whichap`
- Team ID: `T6TF2VZNJL`
- Signing identity: `Developer ID Application: Granger Community Church, INC.`
- Notary keychain profile: `WhichAP-notary` (the only path to ship
  signed builds — back this up if migrating Macs)

### Jamf

- Server: `https://jss.gccwired.com:8443/`
- API client keychain: account `WhichAP-CLI`, service
  `jamf-api-client` (JSON with `client_id` + `client_secret`, OAuth at
  `/api/oauth/token`)
- Computer ID 564 = jpowell2051 (dev Mac)
- Test group ID 299 = "Test WhichAP deploy" (9 Macs)
- Smart group ID 301 = "whichAP <current-version> installed"
  (auto-renamed each release; criterion: Application Version is X.Y.Z)
- Policy ID 204 = "Install WhichAP" (Ongoing, recurring check-in,
  scope=group 299, exclusion=group 301)
- Pre-install script ID 101 = pkill + rm
- Post-install script ID 102 = truncateAtColon default + console launch
- Package ID 314 = "WhichAP-<current-version>-granger" (filename
  updated in place each release)

### RUCKUS

- API client keychain: account `ruckus-claude-code`, service
  `ruckus-api`
- Used by `scripts/ruckus-pull-bssids.sh` to refresh
  `whichap-mapping.json`

### Filesystem

- Source: `/Users/jpowell/Projects/WhichAP/`
- Build artifacts: `build/Release/WhichAP.app`,
  `build/WhichAP-X.Y.Z*.{dmg,pkg}`
- Granger mapping (gitignored): `whichap-mapping.json` (Ruckus format,
  ~173 entries — refresh via script, never hand-edit)
- Public bundled mapping: `WhichAP/Resources/default-mapping.json`
  (~7 example entries, never replace with Granger data)
- App Sandbox container (real connection history):
  `~/Library/Containers/com.grangerchurch.whichap/Data/Library/Application Support/WhichAP/connection-history.json`

## Pointer to release procedure

For the full ship-time runbook (version bump rules, semver criteria,
release order, verification gates), see **`docs/release-checklist.md`**.
The build script reads that file to print post-build manual steps.
