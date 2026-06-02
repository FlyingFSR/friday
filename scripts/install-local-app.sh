#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build-local-app.sh"

TARGET_DIR="/Applications"
if [[ ! -w "$TARGET_DIR" && ! -w "$TARGET_DIR/Friday.app" ]]; then
  TARGET_DIR="$HOME/Applications"
fi
TARGET_APP="$TARGET_DIR/Friday.app"
SOURCE_APP="$APP_ROOT/dist/Friday.app"

echo "Stopping existing Friday processes..."
pkill -f FridayMac || true
pkill -f "/Friday.app/Contents/MacOS/Friday" || true

echo "Building local Friday app bundle..."
bash "$BUILD_SCRIPT"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Error: built app bundle not found at $SOURCE_APP" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
ditto "$SOURCE_APP" "$TARGET_APP"

echo "Installed:"
echo "  $TARGET_APP"

echo "Launching Friday..."
open "$TARGET_APP"

echo "Done."
