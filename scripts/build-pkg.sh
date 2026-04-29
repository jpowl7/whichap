#!/bin/bash
# Build a verified WhichAP .pkg or DMG with structural gates.
#
# Usage:
#   ./scripts/build-pkg.sh public-dmg     # Public DMG (bundled example BSSIDs)
#   ./scripts/build-pkg.sh granger-dmg    # Granger DMG (real BSSIDs, re-signed)
#   ./scripts/build-pkg.sh granger-pkg    # Granger pkg for Jamf
#   ./scripts/build-pkg.sh all            # Build all three in safe order
#
# Hard rules enforced (script aborts on violation):
#   • Public DMG bundled mapping must have ≤10 entries (privacy gate)
#   • Granger DMG/pkg bundled mapping must have ≥10 entries (sanity gate)
#   • Granger pkg payload must start with ./Applications/WhichAP.app
#   • Granger DMG/pkg must be re-signed with --entitlements (4 entitlements
#     verified post-sign)
#   • All produced artifacts must pass codesign --verify --deep --strict
#
# This script does NOT notarize, upload to CasperShare, or modify Jamf.
# Those steps remain manual per docs/release-checklist.md.

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

# ── Constants ─────────────────────────────────────────────────────────────
APP_NAME="WhichAP.app"
RELEASE_APP="build/Release/${APP_NAME}"
GRANGER_MAPPING="whichap-mapping.json"
ENTITLEMENTS="WhichAP/WhichAP.entitlements"
SIGN_IDENTITY="Developer ID Application: Granger Community Church, INC. (T6TF2VZNJL)"
DMG_BG="/tmp/dmg-background.png"
INFO_PLIST="WhichAP/Info.plist"

PUBLIC_MAPPING_MAX=10        # ≤ this many entries → safe for public
GRANGER_MAPPING_MIN=10       # ≥ this many entries → real Granger data present

# ── Output helpers ────────────────────────────────────────────────────────
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[34m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
fail()  { red "✗ $*"; exit 1; }
pass()  { green "✓ $*"; }
step()  { blue "→ $*"; }
warn()  { yellow "! $*"; }

# ── Read version from Info.plist ──────────────────────────────────────────
get_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${RELEASE_APP}/Contents/${INFO_PLIST##*/}" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST}"
}

get_build_number() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${RELEASE_APP}/Contents/Info.plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${INFO_PLIST}"
}

# ── Count entries in a default-mapping.json (handles both formats) ────────
count_mapping_entries() {
    local path="$1"
    python3 - "$path" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
if isinstance(d, list):
    print(len(d))
elif isinstance(d, dict) and 'result' in d:
    print(sum(len(r.get('data', [])) for r in d['result']))
else:
    print(0)
PY
}

# ── Verify the codesigned bundle has all 4 entitlements ───────────────────
# (Avoid pipefail SIGPIPE: capture output first, search the variable.)
verify_entitlements() {
    local app="$1"
    local required=(
        "com.apple.security.app-sandbox"
        "com.apple.security.files.user-selected.read-only"
        "com.apple.security.network.client"
        "com.apple.security.personal-information.location"
    )
    local out
    out=$(codesign -d --entitlements - "$app" 2>&1) \
      || fail "codesign --entitlements failed on $app"
    for e in "${required[@]}"; do
        if [[ "$out" != *"$e"* ]]; then
            fail "Missing entitlement on $app: $e"
        fi
    done
}

# ── Verify codesigning and Designated Requirement ─────────────────────────
# (Capture output first to avoid pipefail SIGPIPE with grep -q.)
verify_codesign() {
    local app="$1"
    codesign --verify --deep --strict "$app" 2>&1 \
      || fail "codesign --verify failed on $app"
    local out
    out=$(codesign -dvv "$app" 2>&1) \
      || fail "codesign -dvv failed on $app"
    if [[ "$out" != *"Granger Community Church"* ]]; then
        fail "Wrong signing identity on $app (expected Granger)"
    fi
}

# ── Ensure DMG background asset exists ────────────────────────────────────
ensure_dmg_background() {
    if [[ -f "$DMG_BG" ]]; then return; fi
    step "DMG background not found at $DMG_BG; trying to extract from latest existing DMG..."
    local latest_dmg
    latest_dmg=$(ls -1t build/WhichAP-*.dmg 2>/dev/null | head -1 || true)
    if [[ -z "$latest_dmg" ]]; then
        warn "No existing DMG to extract from — DMG will be built without styled background."
        DMG_BG=""
        return
    fi
    hdiutil attach "$latest_dmg" -nobrowse -readonly -quiet
    if [[ -f "/Volumes/WhichAP/.background/dmg-background.png" ]]; then
        cp "/Volumes/WhichAP/.background/dmg-background.png" "$DMG_BG"
        pass "Background extracted to $DMG_BG"
    else
        warn "No background found in $latest_dmg"
        DMG_BG=""
    fi
    hdiutil detach "/Volumes/WhichAP" -quiet 2>/dev/null || true
}

# ── Run create-dmg with consistent styling ────────────────────────────────
make_dmg() {
    local source_dir="$1"
    local output_dmg="$2"
    rm -f "$output_dmg"
    local bg_arg=()
    [[ -n "$DMG_BG" ]] && bg_arg=(--background "$DMG_BG")
    create-dmg \
        --volname "WhichAP" \
        --window-size 540 260 \
        --icon-size 80 \
        --icon "WhichAP.app" 380 120 \
        --app-drop-link 160 120 \
        "${bg_arg[@]}" \
        --no-internet-enable \
        "$output_dmg" \
        "$source_dir" >/dev/null 2>&1 \
      || fail "create-dmg failed for $output_dmg"
}

# ── Print summary block ───────────────────────────────────────────────────
print_summary() {
    local file="$1"
    local kind="$2"
    local size sha
    size=$(stat -f%z "$file")
    sha=$(shasum -a 512 "$file" | awk '{print $1}')

    echo ""
    blue "═══ $kind summary ═══"
    echo "  Path:   $file"
    echo "  Size:   $(printf "%'d" "$size") bytes"
    echo "  SHA512: ${sha:0:32}…${sha: -8}"
    echo ""
    echo "  Full SHA-512 (for Jamf hash field):"
    echo "  $sha"
    echo ""

    case "$kind" in
        granger-pkg)
            echo "  Next manual steps (per docs/release-checklist.md):"
            echo "    1. Test-install locally:"
            echo "       sudo installer -pkg $file -target /"
            echo "    2. Verify version:"
            echo "       /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/WhichAP.app/Contents/Info.plist"
            echo "    3. Upload pkg to CasperShare via SMB"
            echo "    4. Update Jamf package 314 (filename + info + hash via API)"
            ;;
        public-dmg|granger-dmg)
            echo "  Next manual steps:"
            echo "    1. Notarize: xcrun notarytool submit $file --keychain-profile WhichAP-notary --wait"
            echo "    2. Staple:   xcrun stapler staple $file"
            echo "    3. Verify:   xcrun stapler validate $file"
            ;;
    esac
}

# ── public-dmg ────────────────────────────────────────────────────────────
build_public_dmg() {
    step "Building public DMG (with bundled example BSSIDs)..."

    [[ -d "$RELEASE_APP" ]] || fail "$RELEASE_APP not found — run xcodebuild first"

    local version
    version=$(get_version)
    step "Version: $version"

    local mapping="$RELEASE_APP/Contents/Resources/default-mapping.json"
    [[ -f "$mapping" ]] || fail "$mapping missing — Release build is incomplete"

    local n
    n=$(count_mapping_entries "$mapping")
    step "Bundled mapping has $n entries"
    if (( n > PUBLIC_MAPPING_MAX )); then
        fail "PRIVACY VIOLATION: bundled mapping has $n entries, max is $PUBLIC_MAPPING_MAX. Real Granger BSSIDs may be present in build/Release/. Run a clean Xcode build to restore the example mapping."
    fi
    pass "Privacy gate passed (mapping is example data, $n ≤ $PUBLIC_MAPPING_MAX entries)"

    verify_codesign "$RELEASE_APP"
    pass "Codesign verified on Release build"

    local stage="/tmp/WhichAP-public-stage"
    rm -rf "$stage"
    mkdir -p "$stage"
    cp -R "$RELEASE_APP" "$stage/"

    ensure_dmg_background
    local out="build/WhichAP-${version}.dmg"
    step "Creating $out..."
    make_dmg "$stage" "$out"

    pass "Public DMG built: $out"
    print_summary "$out" "public-dmg"
}

# ── granger-dmg ───────────────────────────────────────────────────────────
build_granger_dmg() {
    step "Building Granger DMG (real BSSIDs, re-signed with entitlements)..."

    [[ -d "$RELEASE_APP" ]] || fail "$RELEASE_APP not found — run xcodebuild first"
    [[ -f "$GRANGER_MAPPING" ]] || fail "$GRANGER_MAPPING not found — refresh via scripts/ruckus-pull-bssids.sh"
    [[ -f "$ENTITLEMENTS" ]] || fail "$ENTITLEMENTS not found"

    local version
    version=$(get_version)
    step "Version: $version"

    local stage="/tmp/WhichAP-granger-stage"
    rm -rf "$stage"
    mkdir -p "$stage"
    cp -R "$RELEASE_APP" "$stage/"

    # Swap mapping
    cp "$GRANGER_MAPPING" "$stage/${APP_NAME}/Contents/Resources/default-mapping.json"
    local n
    n=$(count_mapping_entries "$stage/${APP_NAME}/Contents/Resources/default-mapping.json")
    step "Granger mapping has $n entries"
    if (( n < GRANGER_MAPPING_MIN )); then
        fail "Granger mapping has only $n entries — expected ≥$GRANGER_MAPPING_MIN. $GRANGER_MAPPING may be stale or wrong file."
    fi
    pass "Granger mapping sanity gate passed ($n ≥ $GRANGER_MAPPING_MIN)"

    # Re-sign with entitlements (the 1.8.4 fix)
    step "Re-signing with --entitlements..."
    codesign --force --deep \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$stage/${APP_NAME}" >/dev/null 2>&1 \
      || fail "codesign re-sign failed"

    verify_codesign "$stage/${APP_NAME}"
    verify_entitlements "$stage/${APP_NAME}"
    pass "Codesign + entitlements verified"

    ensure_dmg_background
    local out="build/WhichAP-${version}-granger.dmg"
    step "Creating $out..."
    make_dmg "$stage" "$out"

    pass "Granger DMG built: $out"
    print_summary "$out" "granger-dmg"
}

# ── granger-pkg ───────────────────────────────────────────────────────────
build_granger_pkg() {
    step "Building Granger pkg for Jamf..."

    [[ -d "$RELEASE_APP" ]] || fail "$RELEASE_APP not found — run xcodebuild first"
    [[ -f "$GRANGER_MAPPING" ]] || fail "$GRANGER_MAPPING not found"
    [[ -f "$ENTITLEMENTS" ]] || fail "$ENTITLEMENTS not found"

    local version
    version=$(get_version)
    local build_num
    build_num=$(get_build_number)
    step "Version: $version (build $build_num)"

    # Stage with Applications/ parent — THE structural fix from 2026-04-28
    local stage="/tmp/whichap-pkg-clean"
    rm -rf "$stage"
    mkdir -p "$stage/Applications"
    cp -R "$RELEASE_APP" "$stage/Applications/${APP_NAME}"
    pass "Staged at $stage/Applications/${APP_NAME} (Applications/ parent verified)"

    # Swap mapping
    cp "$GRANGER_MAPPING" "$stage/Applications/${APP_NAME}/Contents/Resources/default-mapping.json"
    local n
    n=$(count_mapping_entries "$stage/Applications/${APP_NAME}/Contents/Resources/default-mapping.json")
    if (( n < GRANGER_MAPPING_MIN )); then
        fail "Granger mapping has only $n entries — expected ≥$GRANGER_MAPPING_MIN"
    fi
    pass "Granger mapping sanity gate passed ($n entries)"

    # Re-sign with entitlements
    step "Re-signing with --entitlements..."
    codesign --force --deep \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$stage/Applications/${APP_NAME}" >/dev/null 2>&1 \
      || fail "codesign re-sign failed"

    verify_codesign "$stage/Applications/${APP_NAME}"
    verify_entitlements "$stage/Applications/${APP_NAME}"
    pass "Codesign + entitlements verified"

    # Generate component plist via pkgbuild --analyze, then flip BundleIsRelocatable=false
    local plist="/tmp/whichap-component.plist"
    rm -f "$plist"
    pkgbuild --analyze --root "$stage" "$plist" >/dev/null 2>&1 \
      || fail "pkgbuild --analyze failed"

    /usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$plist"
    pass "Component plist generated, BundleIsRelocatable=false"

    # Build pkg
    local out="build/WhichAP-${version}-granger.pkg"
    rm -f "$out"
    pkgbuild \
        --root "$stage" \
        --component-plist "$plist" \
        --identifier com.grangerchurch.whichap \
        --version "$version" \
        --install-location / \
        "$out" >/dev/null 2>&1 \
      || fail "pkgbuild failed"

    # 🔴 GATE: payload must start with ./Applications/WhichAP.app
    # Capture full payload listing first to avoid SIGPIPE with head/tail.
    local payload first_path app_path
    payload=$(pkgutil --payload-files "$out" 2>/dev/null) \
      || fail "pkgutil --payload-files failed on $out"
    first_path=$(awk 'NR==2' <<< "$payload")
    app_path=$(awk 'NR==3' <<< "$payload")
    if [[ "$first_path" != "./Applications" ]]; then
        fail "Payload structure wrong. Expected './Applications' at line 2, got: '$first_path'"
    fi
    if [[ "$app_path" != "./Applications/${APP_NAME}" ]]; then
        fail "Payload structure wrong. Expected './Applications/${APP_NAME}' at line 3, got: '$app_path'"
    fi
    pass "Payload layout gate passed (./Applications/${APP_NAME})"

    # Verify PackageInfo bundle path
    local pkg_info_dir="/tmp/pkg-inspect-$$"
    rm -rf "$pkg_info_dir"
    mkdir -p "$pkg_info_dir"
    (cd "$pkg_info_dir" && xar -xf "${PROJECT_ROOT}/$out" PackageInfo) 2>/dev/null
    if [[ ! -f "$pkg_info_dir/PackageInfo" ]]; then
        rm -rf "$pkg_info_dir"
        fail "Could not extract PackageInfo from $out"
    fi
    local pkg_info
    pkg_info=$(<"$pkg_info_dir/PackageInfo")
    rm -rf "$pkg_info_dir"
    if [[ "$pkg_info" != *'<bundle path="./Applications/WhichAP.app"'* ]]; then
        fail "PackageInfo bundle path is not ./Applications/WhichAP.app"
    fi
    pass "PackageInfo bundle path verified"

    pass "Granger pkg built: $out"
    print_summary "$out" "granger-pkg"
}

# ── Main ──────────────────────────────────────────────────────────────────
TARGET="${1:-}"
case "$TARGET" in
    public-dmg)
        build_public_dmg
        ;;
    granger-dmg)
        build_granger_dmg
        ;;
    granger-pkg)
        build_granger_pkg
        ;;
    all)
        build_public_dmg
        build_granger_dmg
        build_granger_pkg
        ;;
    *)
        cat <<EOF
Usage: $0 [public-dmg|granger-dmg|granger-pkg|all]

  public-dmg    Public DMG (bundled example BSSIDs only — privacy gate)
  granger-dmg   Granger DMG (real BSSIDs, re-signed with entitlements)
  granger-pkg   Granger pkg for Jamf (correct layout + payload gate)
  all           Build all three in safe order

See docs/release-checklist.md for the full ship-time procedure.
EOF
        exit 2
        ;;
esac
