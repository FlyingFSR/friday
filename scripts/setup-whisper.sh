#!/usr/bin/env bash
set -euo pipefail

# Friday talks to whisper-server over HTTP at runtime, so that is the binary it
# needs on PATH when running from source. Homebrew's whisper-cpp formula ships it.
if command -v whisper-server >/dev/null 2>&1; then
  echo "whisper-server already installed: $(command -v whisper-server)"
  exit 0
fi

if command -v brew >/dev/null 2>&1; then
  echo "Installing whisper.cpp via Homebrew..."
  brew install whisper-cpp
  echo "Done. whisper-server path: $(command -v whisper-server)"
  exit 0
fi

echo "Homebrew not found. Install whisper.cpp manually:"
echo "  git clone https://github.com/ggerganov/whisper.cpp"
echo "  cd whisper.cpp"
echo "  cmake -B build && cmake --build build -j --config Release"
echo "  sudo cp ./build/bin/whisper-server /usr/local/bin/whisper-server"
exit 1
