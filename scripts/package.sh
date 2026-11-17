#!/bin/zsh
# Builds a Release SipBuddy.app and wraps it in a drag-to-install DMG plus a zip.
# Usage: ./scripts/package.sh            (ad-hoc signed, for your own Mac)
#        SIGN_ID="Developer ID Application: Name (TEAMID)" ./scripts/package.sh   (for distribution)
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="${SIGN_ID:--}"
DIST=dist
rm -rf build/Release-pkg "$DIST" && mkdir -p "$DIST"

xcodebuild -project SipBuddy.xcodeproj -scheme SipBuddy -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath build/Release-pkg CODE_SIGN_IDENTITY="$SIGN_ID" ONLY_ACTIVE_ARCH=NO build | grep -E "error:|BUILD"

APP=build/Release-pkg/Build/Products/Release/SipBuddy.app
codesign --verify --deep --strict "$APP"
cp -R "$APP" "$DIST/"

ditto -c -k --keepParent "$DIST/SipBuddy.app" "$DIST/SipBuddy.zip"

STAGE=$(mktemp -d)
cp -R "$DIST/SipBuddy.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
for i in 1 2 3; do hdiutil create -volname SipBuddy -srcfolder "$STAGE" -ov -fs HFS+ -format UDZO "$DIST/SipBuddy.dmg" >/dev/null && break; sleep 2; done
rm -rf "$STAGE"

echo "Packaged:"
ls -lh "$DIST"
