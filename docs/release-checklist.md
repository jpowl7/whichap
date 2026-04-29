# WhichAP release checklist

The end-to-end ship-time procedure. The build script reads this file and
prints post-build steps to console. Items marked **🔴 GATE** must pass or
the release is aborted.

## When to bump which version

WhichAP follows semver via `CFBundleShortVersionString` (X.Y.Z) plus an
incrementing `CFBundleVersion` (build int).

- **Major (X bump):** breaking change to persisted data schema, breaking
  change to Jamf integration, or other change requiring a coordinated
  Granger-side action. Rare — last was never. We're at v1.x.
- **Minor (Y bump):** new user-visible feature, new Preferences option,
  schema additions that are backward-compatible (e.g., 1.9.0's optional
  `priorRSSI`/`channel` Codable fields).
- **Patch (Z bump):** bug fix, UI polish, copy update, dependency bump,
  or internal refactor with no user-visible change.
- **Build (`CFBundleVersion`):** always increments by 1 on any release,
  regardless of major/minor/patch.

If unsure, bump higher rather than lower. It's easier to explain "1.10.0
turned out to be just a polish release" than the reverse.

## Pre-flight (before touching code)

- [ ] Working tree clean (`git status` empty or known)
- [ ] Decide semver bump: major / minor / patch (see above)
- [ ] Identify what's user-visible — those need HelpWindow + README
      updates

## Code phase

- [ ] Bump `CFBundleShortVersionString` and `CFBundleVersion` in
      `WhichAP/Info.plist`
- [ ] Update `WhichAP/HelpWindow.swift` if any user-visible feature
      changed
- [ ] Update `README.md` features list if any user-visible feature
      changed
- [ ] Update `CHANGELOG.md` (when it exists) with rationale: what
      changed, why this is major/minor/patch
- [ ] **🔴 GATE:** Run a 5-minute CPU test on the running build:
      `top -l 30 -s 10 -pid $(pgrep -x WhichAP) -stats pid,cpu,mem,threads,time`.
      Pass: ≤0.1% sustained CPU, stable RSS, no thread growth.
- [ ] Commit with descriptive message
- [ ] Tag git: `git tag vX.Y.Z`

## Build phase

Run via `scripts/build-pkg.sh all` — automated end-to-end with verification
gates. Or build artifacts individually:

- [ ] `scripts/build-pkg.sh public-dmg` — public DMG with bundled example
      mapping
  - **🔴 GATE:** `WhichAP.app/Contents/Resources/default-mapping.json`
    must have ≤10 entries with `AA:BB:CC:` BSSID prefix. Refuses to
    publish otherwise — this is the privacy gate.
- [ ] `scripts/build-pkg.sh granger-dmg` — Granger DMG (real BSSIDs,
      re-signed with entitlements)
  - **🔴 GATE:** mapping must have ≥10 entries (sanity check that real
    data is present, not the example placeholder)
- [ ] `scripts/build-pkg.sh granger-pkg` — Granger pkg for Jamf
  - **🔴 GATE:** `pkgutil --payload-files <pkg> | head -2` second line
    must be exactly `./Applications/WhichAP.app` (matches 1.8.4 layout)
- [ ] **🔴 GATE:** Test-install pkg locally (manual sudo, can't be
      automated):
      `sudo installer -pkg build/WhichAP-X.Y.Z-granger.pkg -target /`.
      Verify `/Applications/WhichAP.app` reads version X.Y.Z. Refuse to
      upload to CasperShare otherwise.

## Notarization

- [ ] Notarize public DMG: `xcrun notarytool submit <dmg>
      --keychain-profile WhichAP-notary --wait`
- [ ] Notarize Granger DMG (same command, different file)
- [ ] **Staple BOTH:** `xcrun stapler staple <dmg>` (easy to forget the
      staple step — it embeds the ticket in the DMG so offline
      Gatekeeper accepts it)
- [ ] Verify staple: `xcrun stapler validate <dmg>` returns "worked"
- [ ] (Optional) `spctl --assess` on the .app inside each mounted DMG

Pkg does NOT need notarization (Jamf handles MDM trust).

## Distribution — public

- [ ] Push commit + tag: `git push origin main && git push origin
      vX.Y.Z`
- [ ] Create GitHub release: `gh release create vX.Y.Z --title "WhichAP
      X.Y.Z" --notes "..." build/WhichAP-X.Y.Z.dmg`

## Distribution — Granger (Jamf)

- [ ] SMB-upload `build/WhichAP-X.Y.Z-granger.pkg` to CasperShare
      (overwrites prior file, same filename pattern). Manual via Finder
      or `mount_smbfs`.
- [ ] Update Jamf package 314 via API: name →
      `WhichAP-X.Y.Z-granger`, filename → `WhichAP-X.Y.Z-granger.pkg`,
      info → `X.Y.Z`
- [ ] Compute SHA-512 locally: `shasum -a 512 <pkg>` and PUT to Jamf
      package 314 `hash_value` (or use Jamf UI "Calculate Checksums")
- [ ] Update smart group 301 via API: rename to
      `whichAP X.Y.Z installed`, change criterion `Application Version
      is X.Y.Z`
- [ ] **🔴 GATE: One-Mac canary test**
  - Save snapshot: GET policy 204, save to
    `/tmp/policy-204-original.xml`
  - PUT policy 204 with scope narrowed to computer 564 only
    (jpowell2051), enabled=true
  - On dev Mac: `sudo jamf policy -id 204` OR Self Service install
  - Verify `/var/log/jamf.log`: `Successfully installed
    WhichAP-X.Y.Z-granger`
  - Verify `/Applications/WhichAP.app` reads X.Y.Z
  - PUT policy 204 back from snapshot, enabled=true, scope restored to
    group 299
- [ ] Re-arm rollout poll (`/loop 20m check rollout...`) until
      reasonable cutoff time. Watch smart group 301 grow toward 9
      members.

## Post-deploy verification

- [ ] Smart group 301 membership = test group 299 membership over the
      next hour (allow time for offline Macs to come online and check
      in)
- [ ] No errors in `/var/log/jamf.log` on test Macs you can sample
- [ ] Crash reports (if Sentry exists) clean for the new build

## Recovery — if a release goes wrong

- Disable policy 204 immediately:
  `curl -X PUT ... -d '<policy><general><enabled>false</enabled></general></policy>'`
- This stops the bleed without affecting non-test Macs.
- See `docs/runbook.md` (when it exists) for full recovery procedures.
