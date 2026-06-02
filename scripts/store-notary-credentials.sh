#!/usr/bin/env bash
set -euo pipefail

PROFILE="${FRIDAY_NOTARY_PROFILE:-FridayNotary}"
APPLE_ID="${FRIDAY_APPLE_ID:-}"
TEAM_ID="${FRIDAY_TEAM_ID:-}"
APP_PASSWORD="${FRIDAY_APP_PASSWORD:-}"

if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APP_PASSWORD" ]]; then
  cat <<'EOF'
Missing required env vars.

Please set:
- FRIDAY_APPLE_ID           (example: you@example.com)
- FRIDAY_TEAM_ID            (example: ABCD123456)
- FRIDAY_APP_PASSWORD       (app-specific password, not your Mac login password)

Optional:
- FRIDAY_NOTARY_PROFILE     (default: FridayNotary)

Example:
FRIDAY_APPLE_ID="you@example.com" \
FRIDAY_TEAM_ID="ABCD123456" \
FRIDAY_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
bash apps/friday-mac/scripts/store-notary-credentials.sh
EOF
  exit 1
fi

echo "Storing notarization credentials into Keychain profile: $PROFILE"
xcrun notarytool store-credentials "$PROFILE" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD"

echo "Stored successfully."
