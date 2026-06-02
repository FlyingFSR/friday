#!/usr/bin/env bash
set -euo pipefail

if command -v whisper-cli >/dev/null 2>&1; then
  echo "whisper-cli already installed: $(command -v whisper-cli)"
  exit 0
fi

if command -v brew >/dev/null 2>&1; then
  echo "Installing whisper.cpp via Homebrew..."
  brew install whisper-cpp
  echo "Done. whisper-cli path: $(command -v whisper-cli)"
  exit 0
fi

echo "Homebrew not found. Install whisper.cpp manually:"
echo "  git clone https://github.com/ggerganov/whisper.cpp"
echo "  cd whisper.cpp"
echo "  make"
echo "  sudo cp ./build/bin/whisper-cli /usr/local/bin/whisper-cli"
exit 1
