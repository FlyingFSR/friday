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
SHORT_VERSION="${FRIDAY_SHORT_VERSION:-0.2.0}"
# The app talks to whisper-server over HTTP at runtime, so that is the binary we
# bundle. FRIDAY_WHISPER_SERVER_PATH overrides autodetection (default: whisper-server on PATH).
WHISPER_SERVER_SOURCE="${FRIDAY_WHISPER_SERVER_PATH:-}"
MEDIUM_MODEL_SOURCE="${FRIDAY_MEDIUM_MODEL_PATH:-$HOME/Library/Application Support/Friday/models/ggml-medium.bin}"
BUNDLE_MEDIUM_MODEL="${FRIDAY_BUNDLE_MEDIUM_MODEL:-0}"

sign_app_bundle_ad_hoc() {
  local binary

  while IFS= read -r -d '' binary; do
    codesign --force --sign - "$binary"
  done < <(find "$FRAMEWORKS_DIR" -type f -name '*.dylib' -print0)

  codesign --force --sign - "$MACOS_DIR/whisper-server"
  codesign --force --sign - "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

copy_whisper_runtime() {
  local server_source="$1"
  local server_target="$MACOS_DIR/whisper-server"

  if [[ -z "$server_source" ]]; then
    if command -v whisper-server >/dev/null 2>&1; then
      server_source="$(command -v whisper-server)"
    else
      echo "Error: whisper-server not found." >&2
      echo "Install whisper.cpp first or set FRIDAY_WHISPER_SERVER_PATH." >&2
      exit 1
    fi
  fi

  if [[ ! -x "$server_source" ]]; then
    echo "Error: whisper-server source is not executable: $server_source" >&2
    exit 1
  fi

  echo "Bundling whisper runtime from: $server_source"
  cp "$server_source" "$server_target"
  chmod +x "$server_target"

  mkdir -p "$FRAMEWORKS_DIR"

  local lib_roots=()
  local server_dir
  server_dir="$(cd "$(dirname "$server_source")" && pwd)"
  lib_roots+=("$server_dir/../libexec/lib")
  lib_roots+=("$server_dir/../lib")
  lib_roots+=("/opt/homebrew/opt/whisper-cpp/libexec/lib")
  lib_roots+=("/usr/local/opt/whisper-cpp/libexec/lib")

  local required_libs=()
  while IFS= read -r lib_name; do
    required_libs+=("$lib_name")
  done < <(
    otool -L "$server_source" \
      | awk '/@rpath\/lib.*\.dylib/ { gsub(/.*@rpath\//, "", $1); print $1 }'
  )

  if [[ "${#required_libs[@]}" -eq 0 ]]; then
    echo "Error: no whisper runtime libraries were detected from whisper-server." >&2
    exit 1
  fi

  local lib_name
  for lib_name in "${required_libs[@]}"; do
    local src=""
    local root
    for root in "${lib_roots[@]}"; do
      if [[ -f "$root/$lib_name" ]]; then
        src="$root/$lib_name"
        break
      fi
    done

    if [[ -z "$src" ]]; then
      echo "Error: required whisper library not found: $lib_name" >&2
      echo "Searched roots:" >&2
      printf '  - %s\n' "${lib_roots[@]}" >&2
      exit 1
    fi

    cp -L "$src" "$FRAMEWORKS_DIR/$lib_name"
    chmod +x "$FRAMEWORKS_DIR/$lib_name"
  done

  # Point whisper-server to bundled libraries.
  for lib_name in "${required_libs[@]}"; do
    install_name_tool -change "@rpath/$lib_name" "@executable_path/../Frameworks/$lib_name" "$server_target"
  done

  # Rewrite bundled library dependencies to load sibling bundled libraries.
  local dylib
  for dylib in "$FRAMEWORKS_DIR"/lib*.dylib; do
    [[ -f "$dylib" ]] || continue
    local base
    base="$(basename "$dylib")"
    install_name_tool -id "@loader_path/$base" "$dylib"

    local dep
    while IFS= read -r dep; do
      install_name_tool -change "@rpath/$dep" "@loader_path/$dep" "$dylib"
    done < <(
      otool -L "$dylib" \
        | awk '/@rpath\/lib.*\.dylib/ { gsub(/.*@rpath\//, "", $1); print $1 }'
    )
  done
}

bundle_medium_model() {
  if [[ "$BUNDLE_MEDIUM_MODEL" != "1" ]]; then
    echo "Skipping medium model bundling (FRIDAY_BUNDLE_MEDIUM_MODEL=$BUNDLE_MEDIUM_MODEL)"
    return
  fi

  if [[ ! -f "$MEDIUM_MODEL_SOURCE" ]]; then
    echo "Error: medium model not found at: $MEDIUM_MODEL_SOURCE" >&2
    echo "Set FRIDAY_MEDIUM_MODEL_PATH or download medium model first." >&2
    exit 1
  fi

  local target_dir="$RESOURCES_DIR/models"
  mkdir -p "$target_dir"
  echo "Bundling medium model from: $MEDIUM_MODEL_SOURCE"
  cp "$MEDIUM_MODEL_SOURCE" "$target_dir/ggml-medium.bin"
}

echo "Building FridayMac in release mode..."
(
  cd "$APP_ROOT"
  swift build -c release
)

BIN_DIR="$(
  cd "$APP_ROOT"
  swift build -c release --show-bin-path
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
cp "$ICON_ICNS" "$RESOURCES_DIR/Friday.icns"

copy_whisper_runtime "$WHISPER_SERVER_SOURCE"
bundle_medium_model

BUNDLE_VERSION="$(date "+%Y%m%d%H%M%S")"
sed \
  -e "s/__BUNDLE_VERSION__/$BUNDLE_VERSION/g" \
  -e "s/__BUNDLE_IDENTIFIER__/$BUNDLE_IDENTIFIER/g" \
  -e "s/__SHORT_VERSION__/$SHORT_VERSION/g" \
  "$PLIST_TEMPLATE" > "$CONTENTS_DIR/Info.plist"

# Packaging guard: the runtime execs a bundled whisper-server. Fail loudly if it
# is missing so a broken package can never reach a release (see issue #1).
if [[ ! -x "$MACOS_DIR/whisper-server" ]]; then
  echo "Error: packaging guard failed — $MACOS_DIR/whisper-server is missing or not executable." >&2
  echo "The released app would be unable to transcribe on a machine without whisper.cpp installed." >&2
  exit 1
fi

# Packaging guard: bundled binaries must not load whisper libraries from a host
# Homebrew/rpath location, or a fresh machine without whisper.cpp would fail.
if otool -L "$MACOS_DIR/whisper-server" | grep -Eq '@rpath/lib(whisper|ggml)'; then
  echo "Error: packaging guard failed — whisper-server still references @rpath whisper libraries:" >&2
  otool -L "$MACOS_DIR/whisper-server" | grep '@rpath' >&2
  exit 1
fi

sign_app_bundle_ad_hoc

echo "Built local app bundle:"
echo "  $APP_BUNDLE"
