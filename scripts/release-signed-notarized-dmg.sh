#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build-local-app.sh"

DIST_DIR="$APP_ROOT/dist"
APP_BUNDLE="$DIST_DIR/Friday.app"
DMG_PATH="$DIST_DIR/Friday.dmg"

SIGN_IDENTITY="${FRIDAY_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${FRIDAY_NOTARY_PROFILE:-FridayNotary}"
TEAM_ID="${FRIDAY_TEAM_ID:-}"
APPLE_ID="${FRIDAY_APPLE_ID:-}"
APP_PASSWORD="${FRIDAY_APP_PASSWORD:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  cat <<'EOF'
Missing FRIDAY_SIGN_IDENTITY.

Set it to your Developer ID Application certificate name, for example:
FRIDAY_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
EOF
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
  echo "Signing identity not found in keychain:"
  echo "  $SIGN_IDENTITY"
  echo
  echo "Run this to inspect available identities:"
  echo "  security find-identity -v -p codesigning"
  exit 1
fi

echo "Building app bundle..."
bash "$BUILD_SCRIPT"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

echo "Codesigning app bundle with hardened runtime..."
codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create -volname "Friday" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "Codesigning DMG..."
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

echo "Submitting DMG to Apple notarization service..."
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
else
  if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APP_PASSWORD" ]]; then
    cat <<'EOF'
No usable notary profile found, and Apple credentials are incomplete.

Choose one:
1) Store credentials once (recommended):
   FRIDAY_APPLE_ID=... FRIDAY_TEAM_ID=... FRIDAY_APP_PASSWORD=... \
   bash apps/friday-mac/scripts/store-notary-credentials.sh

2) Or provide env vars directly for this run:
   FRIDAY_APPLE_ID, FRIDAY_TEAM_ID, FRIDAY_APP_PASSWORD
EOF
    exit 1
  fi

  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait
fi

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler staple "$DMG_PATH"

echo "Local Gatekeeper assessment..."
spctl -a -vv --type exec "$APP_BUNDLE" || true
spctl -a -vv --type open "$DMG_PATH" || true

echo "Release ready:"
echo "  App: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"
