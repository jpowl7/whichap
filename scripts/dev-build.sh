#!/bin/bash
# Build, bake the Granger mapping into the bundle, re-sign with entitlements,
# kill any running instance, and launch — for local testing only.
# Usage:  ./scripts/dev-build.sh
set -e
cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
APP="build/Release/WhichAP.app"
MAPPING="whichap-mapping.json"
SIGN_IDENTITY="Developer ID Application: Granger Community Church, INC. (T6TF2VZNJL)"
ENTITLEMENTS="WhichAP/WhichAP.entitlements"

echo "→ Killing existing WhichAP process..."
pkill -x WhichAP 2>/dev/null || true
sleep 1

echo "→ Building Release (output: /tmp/whichap-build.log)..."
xcodebuild build \
  -project WhichAP.xcodeproj \
  -scheme WhichAP \
  -configuration Release \
  -destination "platform=macOS" \
  CONFIGURATION_BUILD_DIR=build/Release \
  > /tmp/whichap-build.log 2>&1 || {
    echo "✗ BUILD FAILED — last 30 lines:"
    tail -30 /tmp/whichap-build.log
    exit 1
}

if [ -f "$MAPPING" ]; then
  echo "→ Baking $MAPPING into bundle as default-mapping.json..."
  cp "$MAPPING" "$APP/Contents/Resources/default-mapping.json"

  echo "→ Re-signing with entitlements..."
  codesign --force --deep \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime --timestamp \
    "$APP" 2>&1 | grep -v "replacing existing signature" || true
else
  echo "⚠ No $MAPPING found at $PROJECT_ROOT/$MAPPING — using example bundled mapping"
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")

echo "→ Launching WhichAP $VERSION (build $BUILD)..."
open -n "$APP"
echo "✓ Done."
