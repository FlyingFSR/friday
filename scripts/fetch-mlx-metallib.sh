#!/usr/bin/env bash
# Provides mlx.metallib, the compiled Metal shader library MLX needs at runtime.
#
# Friday builds with SwiftPM's native build system, which does not compile Metal
# shaders, so the library comes from Apple's official mlx-metal wheel on PyPI.
# It must match the MLX core inside mlx-swift 0.32.3 (Package.swift), which is 0.32.2.
#
# Usage:
#   bash scripts/fetch-mlx-metallib.sh            # prints the path of the cached metallib
#   bash scripts/fetch-mlx-metallib.sh --dev      # also copies it next to .build/{debug,release} binaries
#
# Environment:
#   FRIDAY_MLX_METAL_WHEEL   use an already downloaded wheel instead of downloading (checksum still enforced)
#   FRIDAY_MLX_METAL_TARGET  wheel build: 14 (default, matches Friday's minimum macOS), 15 or 26
#   FRIDAY_DOWNLOAD_LIMIT    optional curl --limit-rate value, e.g. 12M
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$APP_ROOT/.build/mlx-metallib"
VERSION="0.32.2"
TARGET="${FRIDAY_MLX_METAL_TARGET:-14}"

case "$TARGET" in
  14)
    WHEEL="mlx_metal-$VERSION-py3-none-macosx_14_0_arm64.whl"
    SHA256="3825fff379dbc107dd3413e564a06caeaa24819910ec49c0439e454c06a1b9b8"
    URL="https://files.pythonhosted.org/packages/f7/ab/ba1952908c5d2a5070cf1cfbfea0161c4751ea62299e2776819810917483/$WHEEL"
    ;;
  15)
    WHEEL="mlx_metal-$VERSION-py3-none-macosx_15_0_arm64.whl"
    SHA256="55a369250d220b2cf10213a87a2ac1b1a420608c5b35b1df4e7147ac8e32f121"
    URL="https://files.pythonhosted.org/packages/79/ec/34f37376e26d537fadffb99af3a760d6545e37f5e1a30a552baadf237fc5/$WHEEL"
    ;;
  26)
    WHEEL="mlx_metal-$VERSION-py3-none-macosx_26_0_arm64.whl"
    SHA256="e6abeac9ac5265830c9c1541b6f96e9be37a85c2446763a46ad466c63a3837ab"
    URL="https://files.pythonhosted.org/packages/dd/cd/4e50bf325100e7165e13d025f264362bf0009196269f9eaf87f2c6e738a2/$WHEEL"
    ;;
  *)
    echo "Error: FRIDAY_MLX_METAL_TARGET must be 14, 15 or 26 (got $TARGET)" >&2
    exit 1
    ;;
esac

METALLIB="$CACHE_DIR/macos$TARGET/mlx.metallib"

if [[ ! -s "$METALLIB" ]]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT

  if [[ -n "${FRIDAY_MLX_METAL_WHEEL:-}" ]]; then
    cp "$FRIDAY_MLX_METAL_WHEEL" "$WORK/$WHEEL"
  else
    echo "Downloading $WHEEL from PyPI..." >&2
    curl -fL ${FRIDAY_DOWNLOAD_LIMIT:+--limit-rate "$FRIDAY_DOWNLOAD_LIMIT"} -o "$WORK/$WHEEL" "$URL"
  fi

  echo "$SHA256  $WORK/$WHEEL" | shasum -a 256 -c - >&2
  unzip -q -o "$WORK/$WHEEL" "mlx/lib/mlx.metallib" -d "$WORK/x"
  mkdir -p "$(dirname "$METALLIB")"
  mv "$WORK/x/mlx/lib/mlx.metallib" "$METALLIB"
fi

if [[ "${1:-}" == "--dev" ]]; then
  for config in debug release; do
    bin_dir="$APP_ROOT/.build/$config"
    if [[ -d "$bin_dir" ]]; then
      cp "$METALLIB" "$bin_dir/mlx.metallib"
      echo "Copied mlx.metallib to $bin_dir" >&2
    fi
  done
fi

echo "$METALLIB"
