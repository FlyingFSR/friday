#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$APP_ROOT/dist"
APP_BUNDLE="$DIST_DIR/Friday.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

PLIST_TEMPLATE="$APP_ROOT/Resources/Info.plist.template"
ICONSET_DIR="$APP_ROOT/Resources/AppIcon.iconset"
ICON_ICNS="$APP_ROOT/Resources/Friday.icns"

BUNDLE_IDENTIFIER="${FRIDAY_BUNDLE_IDENTIFIER:-com.fw.friday.local}"
SHORT_VERSION="${FRIDAY_SHORT_VERSION:-0.5.0}"
# MLX loads its Metal shader library from a SwiftPM-style resource bundle inside the
# app's Resources (see mlx-swift device.cpp, load_swiftpm_library). It must match the
# MLX core pinned in Package.swift; scripts/fetch-mlx-metallib.sh provides it.
METALLIB_BUNDLE_DIR="$RESOURCES_DIR/mlx-swift_Cmlx.bundle"

sign_app_bundle_ad_hoc() {
  local binary

  while IFS= read -r -d '' binary; do
    codesign --force --sign - "$binary"
  done < <(find "$FRAMEWORKS_DIR" -type f -name '*.dylib' -print0)

  codesign --force --sign - "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

METALLIB_SOURCE="$(bash "$SCRIPT_DIR/fetch-mlx-metallib.sh")"

echo "Building FridayMac in release mode..."
(
  cd "$APP_ROOT"
  # The native build system skips Metal sources; the shader library is bundled below instead.
  # The prefix maps keep the builder's absolute paths (home folder, user name) out of the
  # binary, which otherwise records them for every Swift and C/C++ source file.
  swift build -c release --build-system native \
    -Xswiftc -file-prefix-map -Xswiftc "$APP_ROOT=." \
    -Xcc "-ffile-prefix-map=$APP_ROOT=." \
    -Xcxx "-ffile-prefix-map=$APP_ROOT=."
)

BIN_DIR="$(
  cd "$APP_ROOT"
  swift build -c release --build-system native --show-bin-path
)"
BIN_PATH="$BIN_DIR/FridayMac"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Error: release binary not found at $BIN_PATH" >&2
  exit 1
fi

if [[ ! -f "$PLIST_TEMPLATE" ]]; then
  echo "Error: Info.plist template not found at $PLIST_TEMPLATE" >&2
  exit 1
fi

if [[ ! -f "$ICON_ICNS" ]]; then
  if [[ -d "$ICONSET_DIR" ]]; then
    echo "Generating Friday.icns from AppIcon.iconset..."
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
  else
    echo "Error: icon resources not found (missing Friday.icns and AppIcon.iconset)" >&2
    exit 1
  fi
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$BIN_PATH" "$MACOS_DIR/Friday"
chmod +x "$MACOS_DIR/Friday"
# Drop the debug map, which lists every object file by its absolute build path.
strip -S "$MACOS_DIR/Friday"
cp "$ICON_ICNS" "$RESOURCES_DIR/Friday.icns"

mkdir -p "$METALLIB_BUNDLE_DIR"
cp "$METALLIB_SOURCE" "$METALLIB_BUNDLE_DIR/default.metallib"

BUNDLE_VERSION="$(date "+%Y%m%d%H%M%S")"
sed \
  -e "s/__BUNDLE_VERSION__/$BUNDLE_VERSION/g" \
  -e "s/__BUNDLE_IDENTIFIER__/$BUNDLE_IDENTIFIER/g" \
  -e "s/__SHORT_VERSION__/$SHORT_VERSION/g" \
  "$PLIST_TEMPLATE" > "$CONTENTS_DIR/Info.plist"

# Packaging guard: without the shader library MLX aborts the app on the first
# dictation ("Failed to load the default metallib"). Fail here instead.
if [[ ! -s "$METALLIB_BUNDLE_DIR/default.metallib" ]]; then
  echo "Error: packaging guard failed — $METALLIB_BUNDLE_DIR/default.metallib is missing." >&2
  exit 1
fi

sign_app_bundle_ad_hoc

echo "Built local app bundle:"
echo "  $APP_BUNDLE"
echo "  speech engine: Qwen3-ASR (in-process), MLX shader library from $METALLIB_SOURCE"
