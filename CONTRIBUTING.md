# Contributing to Friday

Thanks for your interest in improving Friday! This is a small, focused project —
a local-first voice-input tool for macOS — and contributions of all sizes are
welcome, from typo fixes to new features.

## Getting set up

You'll need:

- An Apple Silicon Mac running macOS 13 or later
- A recent Swift toolchain (Xcode or the Swift command-line tools)
- whisper.cpp's `whisper-server` on your `PATH` (`bash scripts/setup-whisper.sh`)

Then:

```bash
swift build
swift test
swift run FridayMac
```

## Project layout

```
Sources/FridayMac/
  App/        # lifecycle, bootstrap, the FridayController and its extensions
  Services/   # audio capture, transcription, paste, hotkey, models, permissions
  UI/         # menu bar, HUD, onboarding
  Models/     # settings and pipeline data types
  Utils/      # helpers (e.g. language detection)
Tests/FridayMacTests/
Resources/    # app icon, Info.plist template
scripts/      # build / install / release / whisper setup
```

## Making a change

1. **Open an issue first** for anything non-trivial, so we can agree on the
   approach before you invest time.
2. Create a branch from `main`.
3. Keep changes focused — one logical change per pull request.
4. Add or update tests when you change behavior. Run `swift test` before pushing.
5. Match the surrounding code style; keep diffs minimal.

## Pull requests

- Describe **what** changed and **why**.
- Note any manual testing you did (this app interacts with macOS permissions,
  the menu bar, and other apps, so describe the real-world behavior you verified).
- Make sure `swift build` and `swift test` pass.

## A couple of things to know

- The menu bar icon (`StatusBarController`) must be created **synchronously**
  during bootstrap, before any async work — otherwise it can fail to appear.
  See `Sources/FridayMac/App/` for the bootstrap ordering.
- Friday is **local-first**. Please don't add features that send audio,
  transcripts, or telemetry off the device without an explicit, opt-in design
  discussion first.

## Reporting bugs

Open an issue with:

- Your macOS version and Mac model (must be Apple Silicon)
- Steps to reproduce
- What you expected vs. what happened
- Relevant console output, if any

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
