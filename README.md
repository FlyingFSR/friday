# Friday

**Local-first voice input for macOS.** Hold a key, speak, release — your words are
transcribed entirely on-device and pasted straight into whatever app you're using.

No cloud, no accounts, no audio ever leaves your Mac. Transcription runs locally
via [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

> Friday lives in your menu bar and stays out of the way until you hold the
> hotkey. It's built for people who think faster than they type and don't want
> to send their voice to someone else's server to do it.

## Features

- **Push-to-talk** — hold `Right Command` to record, release to transcribe.
- **Fully on-device** — transcription via `whisper.cpp`; audio never leaves your machine.
- **Paste anywhere** — text is inserted at your cursor, with clipboard restore afterward.
- **Secure-input aware** — automatically refuses to paste into password fields and other protected contexts.
- **Mixed-language support** — handles speech that switches between languages mid-sentence (e.g. Chinese ↔ English) via voice-activity segmentation.
- **First-run onboarding** — guided setup for permissions and model download.

## Requirements

- Apple Silicon Mac (macOS 13+)
- [`whisper-cli`](https://github.com/ggerganov/whisper.cpp) on your `PATH`
  (or at `/opt/homebrew/bin/whisper-cli`). The packaged app bundles its own copy.

Install `whisper.cpp` quickly:

```bash
bash scripts/setup-whisper.sh   # uses Homebrew if available
```

## Quick Start (from source)

```bash
swift build
swift run FridayMac
```

On first launch, grant the three permissions macOS requires for a voice-input tool:

1. **Microphone** — to capture your speech
2. **Accessibility** — to paste into other apps
3. **Input Monitoring** — to detect the push-to-talk hotkey

Then make sure the **Medium** model is installed, and try it: hold `Right Command`,
speak, release.

## Install as an App

Build, install, and launch `Friday.app` in one step:

```bash
bash scripts/install-local-app.sh
```

- Installs to `/Applications/Friday.app` (falls back to `~/Applications` if needed)
- Launchable by double-clicking in Finder
- Idempotent — safely overwrites a previous install

Build the bundle only, without installing:

```bash
bash scripts/build-local-app.sh
# Output: dist/Friday.app
```

## Models

- Default model: `medium`
- Models download to `~/Library/Application Support/Friday/models`
- A small Silero VAD model (~885 KB) is fetched automatically on first use to
  improve mixed-language accuracy (see [VAD_CHANGELOG.md](VAD_CHANGELOG.md))

## Distributing a Signed Build

To install on another Mac without "unverified developer" warnings, use a
Developer ID signature + Apple notarization.

Store notary credentials once (saved in your Keychain):

```bash
FRIDAY_APPLE_ID="you@example.com" \
FRIDAY_TEAM_ID="ABCD123456" \
FRIDAY_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
bash scripts/store-notary-credentials.sh
```

Build a signed + notarized DMG:

```bash
FRIDAY_SIGN_IDENTITY="Developer ID Application: Your Name (ABCD123456)" \
FRIDAY_NOTARY_PROFILE="FridayNotary" \
bash scripts/release-signed-notarized-dmg.sh
# Output: dist/Friday.dmg
```

The recipient still grants microphone / accessibility / input-monitoring
permissions on first run — that's a macOS security requirement, not optional.

## Privacy

Friday is local-first by design. Your audio is transcribed on your own machine
and is never uploaded, logged remotely, or sent to any third party. Model files
are downloaded directly from their source the first time they're needed.

## Development

```bash
swift build          # build
swift test           # run tests
swift run FridayMac  # run
```

If the menu bar state ever looks stale, do a clean restart:

```bash
pkill -f FridayMac || true
swift build
.build/debug/FridayMac &
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get involved.

## License

[MIT](LICENSE) © Friday Mac contributors
