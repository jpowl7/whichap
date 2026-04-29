# WhichAP Improvement Roadmap

A living checklist of best practices, tools, and processes worth adopting over time. Not everything here needs to be done — read the "skip" notes and pick what fits the project's actual needs. Status checkboxes track progress.

Origin: drafted 2026-04-28 after a deploy failure where a malformed `.pkg` got pushed to production Jamf-managed Macs. The lesson — verification gates need to be structural, not memory-based — drives the prioritization here.

---

## Top 3 (highest ROI)

- [ ] **Build script + CLAUDE.md** (<1 hour, lowest cost) — see "Build & release automation" below. Directly prevents the 1.9.0 pkg-layout class of failure.
- [ ] **Crash reporting via Sentry** (~30 min) — see "Observability" below. Catches problems on coworkers' Macs that you'd otherwise never hear about.
- [ ] **Sparkle auto-updates** (~3 hours) — see "Distribution & updates" below. Replaces the manual "ask users to download a new DMG" workflow for the public release.

Each is independent. Tackle in any order; suggest top to bottom by cost.

---

## 1. Testing & verification

**Worth it:**
- [ ] **Unit test target for parsing logic.** Cover the CSV/JSON mapping parser, `ConnectionEvent` Codable, and the new pattern-flag detection (sticky/ping-pong/slow-roam). Pure logic, easy to test, easy to break in a refactor. Add an `XCTest` target in Xcode, write 10–20 tests covering "what if someone gives me a malformed CSV" and "what if priorRSSI is nil." 1–2 hours total, then runs on every build via `xcodebuild test`.
- [ ] **Pre-deploy verification scripts** (the lesson from 2026-04-28). The build script + CLAUDE.md combo. See top-3 above.
- [ ] **Manual smoke-test checklist before each release.** A markdown file (`docs/release-checklist.md`) with: install via DMG, install via Jamf, launch, click each menu item, restart Wi-Fi, change BSSID source, etc. 10 min per release, catches regressions.

**Skip:**
- UI test automation (XCUITest for menu bar apps is fragile and slow — not worth the maintenance for 9 users)
- Snapshot testing
- TDD as a discipline

## 2. Build & release automation

**Worth it:**
- [ ] **Build scripts in the repo, not in your head.** `dev-build.sh` exists. Add `scripts/build-granger-pkg.sh` (with the Applications/ layout baked in + `pkgutil --payload-files` verification) and `scripts/release.sh 1.10.0` that bumps Info.plist, builds public DMG + Granger DMG + .pkg, notarizes, staples. End state: one command to ship.
- [ ] **Version bumping in one place.** Right now Info.plist has `CFBundleShortVersionString` and `CFBundleVersion` — easy to forget to bump one. A script that does both atomically is worth 20 minutes.
- [ ] **GitHub Actions for build verification.** Every push to GitHub triggers `xcodebuild build` on Apple's macOS runners. Free for public repos, free-ish for private with limits. Catches "I broke the build on a refactor and didn't notice." 30 min to set up. Workflow file goes in `.github/workflows/build.yml`.

**Skip:**
- Multi-stage CI (dev → staging → prod). Overkill for one-person tool.
- Build matrix testing across many macOS versions (only macOS 13+ supported)

## 3. Distribution & updates

**Worth it:**
- [ ] **Sparkle framework for auto-updates** (https://sparkle-project.org). The thing that makes `Cmd+R "Check for Updates"` work in apps like Slack, Bear, Things. Host an `appcast.xml` somewhere (GitHub Pages works fine, free), Sparkle reads it, downloads + installs new versions. Replaces the "ask users to download a new DMG" workflow for the public release. Granger still uses Jamf because that's how managed Macs work, but for public GitHub release Sparkle is a huge UX upgrade.
  - Setup: ~3 hours one-time.
  - Need a static URL where appcast.xml is published — GitHub Pages makes this trivial.

**Skip:**
- Mac App Store. Not worth the $99/year and review friction for an internal tool. Reconsider only if ever sold publicly.

## 4. Observability — knowing when something's broken

This is the biggest current gap. Today if WhichAP crashes on a coworker's Mac, no signal back to you unless they tell you.

**Worth considering:**
- [ ] **Sentry, Bugsnag, or AppCenter.** Drop-in SDK (one Swift Package) that catches crashes, exceptions, ships them to a dashboard with stack traces. Free tier on Sentry covers 5,000 events/month — plenty for 9 Macs. ~30 min to integrate. **Would have caught the location-permission bug coworkers experienced silently before you diagnosed it manually.**
- [ ] **Built-in macOS crash reports.** Lower-effort: in About box or Help window, add a "Send Diagnostic Report" button that pulls `~/Library/Logs/DiagnosticReports/WhichAP_*.crash` and emails it to you. Free, minimal code.

**Skip for now:**
- APM (Datadog, New Relic) — overkill for menu bar utility
- User analytics (Mixpanel) — privacy concerns + no use case

## 5. Code quality

**Worth it:**
- [ ] **SwiftLint** (https://github.com/realm/SwiftLint). Runs as a build phase in Xcode, flags style issues, common bugs (force unwraps, retain cycles), unused vars. ~10 min to add via Homebrew + Xcode build phase.
- [ ] **swift-format** for consistent formatting. Optional companion to SwiftLint.

**Skip:**
- Static analyzers like SonarQube
- Code coverage tooling — not enough tests yet to make coverage % meaningful

## 6. Security & supply chain

**Worth it:**
- [ ] **Dependency hygiene.** WhichAP currently has zero third-party dependencies (good). When adding any (Sparkle, Sentry), pin versions in Package.swift and review updates manually.
- [ ] **Periodic re-signing audit.** Once a year, run `codesign -dvv build/Release/WhichAP.app` and confirm cert hasn't expired. Apple Developer ID certs are 5-year — set a calendar reminder for ~4 years from issue date.
- [ ] **Notarization profile backup.** The `WhichAP-notary` keychain entry is the only path to ship signed/notarized builds. If the dev Mac dies, recovery requires re-creation. Document in `docs/recovery.md` (which `notarytool` profile, what API key was used, where Apple Connect creds live).

**Skip:**
- Reproducible builds (mostly relevant for high-trust open source)
- SBOM (Software Bill of Materials)

## 7. Documentation

**Worth it:**
- [ ] **`docs/architecture.md`** — one page describing how the major pieces fit together: WiFiMonitor delegates → StatusBarController menu updates → ConnectionHistoryStore persistence.
- [ ] **`CHANGELOG.md`** at repo root. Plain text easier to scan than GitHub releases, makes future Claude sessions smarter.
- [ ] **Operational runbook** (`docs/runbook.md`): "How to deploy a new version", "How to add a BSSID mapping", "How to recover from a broken Jamf install" — concrete procedures with commands, not narrative.

**Skip:**
- Code-level docstrings on every method (small enough that names + types tell the story)
- API reference docs (no public API)

## 8. Process / discipline (no tools, just habits)

**Worth it:**
- [ ] **Don't deploy on Friday afternoon or right before bed.** A pre-deploy "is this 11pm? ship tomorrow" gut check pays for itself.
- [ ] **Pre-deploy diff review.** Before any Jamf push, look at what's changing. `git log v1.8.4..v1.9.0` to see commits, `git diff` the working tree.
- [ ] **One-Mac canary first** (the pattern landed on after the 1.9.0 failure). Even if it costs an extra 30 min, scope to one Mac, verify, then widen. Default, not recovery procedure.

---

## How to use this document

- **Pick one item, finish it, check it off.** Don't try to adopt everything at once.
- **Re-evaluate quarterly.** Some items here may turn out not to matter; some not yet on the list will surface as needs change.
- **The "Skip" notes are intentional.** Don't second-guess them without evidence — premature systems often rot.
- **When you finish a top-3 item**, replace it in the top-3 with the next-highest-priority unchecked item from the rest of the doc.

## Changelog

- 2026-04-28: Created post-1.9.0 ship-night failure. Top 3 = Build script + CLAUDE.md / Sentry / Sparkle.
