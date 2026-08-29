# VAD & Mixed-Language — Design History

> **Status: historical design note.** This document records an earlier
> exploration that integrated Silero VAD with the `whisper-cli` code path.
> The runtime has since moved to a long-lived `whisper-server` process, and
> **VAD is disabled by default** in the current build (the Silero model is not
> downloaded unless VAD is enabled). The current transcription path is a
> single-pass request over the whole recording. This note is kept for context on
> the dropped-segment problem and the approaches tried; see
> [issue #4](https://github.com/FlyingFSR/friday/issues/4) for the live tracking
> of mixed-language quality. File paths and flags below describe the older design
> and may not match current code.

## Problem

When the user speaks a long segment that starts in Chinese and then switches to English, the English portion gets dropped from the transcription. Short English phrases at the end may survive, but long English segments disappear entirely.

**Root cause:** whisper-cli with `-l auto` detects the language once from the beginning of the audio and applies it globally. If the beginning is Chinese, the entire audio is processed as Chinese. Long English segments are either hallucinated as Chinese or silently dropped due to the entropy threshold (`-et 2.4`).

Previously tried `-l zh` (force Chinese mode), but that causes English speech to be **translated into Chinese** instead of being preserved as English text.

## Solution: Integrate Silero VAD

Enable whisper-cli's built-in Voice Activity Detection (VAD) to split audio on natural pauses before transcription. This way each speech segment is shorter and more likely to contain only one language, giving `-l auto` a better chance of detecting the correct language per segment.

The VAD model is Silero v6.2.0 in GGML format (~885 KB), downloaded automatically from Hugging Face on first use.

## Files Changed (7 files)

### 1. `Sources/FridayMac/Models/TranscriptionModels.swift`
- Added `vadModelPath: String?` field to `TranscriptionRequest`

### 2. `Sources/FridayMac/App/FridayDependencies.swift`
- Added `ensureVADModelInstalled() async throws -> URL` to the `ModelManaging` protocol

### 3. `Sources/FridayMac/Services/ModelManager.swift`
- Added static constants for VAD model filename (`ggml-silero-v6.2.0.bin`) and download URL (`https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin`)
- Added `ensureVADModelInstalled()` method that downloads the VAD model to the same `~/Library/Application Support/Friday/models/` directory, with caching (only downloads once)

### 4. `Sources/FridayMac/Services/TranscriptionService.swift`
- `buildWhisperArguments` now accepts optional `vadModelPath` parameter
- When language is `auto` AND `vadModelPath` is provided, appends these flags:
  - `--vad` — enable VAD
  - `-vm <path>` — path to Silero VAD model
  - `-vmsd 15` — max speech duration 15s (auto-split longer segments)
  - `-vsd 300` — min silence duration 300ms to trigger a split
  - `-vp 100` — 100ms padding before/after each segment

### 5. `Sources/FridayMac/App/FridayController+Pipeline.swift`
- Before creating `TranscriptionRequest`, checks if language is `auto`
- If so, calls `modelManager.ensureVADModelInstalled()` to get VAD model path
- Uses `try?` so VAD download failure is non-fatal (falls back to original behavior)
- Passes `vadModelPath` into `TranscriptionRequest`

### 6. `Tests/FridayMacTests/TranscriptionServiceArgumentTests.swift`
- Added `autoLanguageWithVADAddsVADFlags` test — verifies VAD flags are present when vadModelPath is provided
- Added `autoLanguageWithoutVADOmitsVADFlags` test — verifies VAD flags are absent when vadModelPath is nil

### 7. `Tests/FridayMacTests/FridayControllerPipelineTests.swift`
- Added `ensureVADModelInstalled()` to `MockModelManager` to satisfy the updated protocol

## Build & Test

```bash
swift build
swift test
```

## What to verify after building

1. First run with `auto` language: the app should automatically download the VAD model (~885 KB) on first transcription
2. Speak a Chinese sentence, pause briefly, then speak an English sentence — both should appear in the output
3. Verify that explicit language mode (e.g. `zh`) still works as before (no VAD flags added)
4. Verify that if the VAD model download fails (e.g. no internet), transcription still works without VAD

## If VAD alone doesn't fully fix it

VAD splits audio on silence boundaries, but whisper may still detect language globally rather than per-segment. If that's the case, the next step would be:
- Implement custom audio segmentation: use an external tool (e.g. ffmpeg with silencedetect) to split the WAV file into chunks, call whisper-cli separately for each chunk with `-l auto`, then concatenate results
- This is more invasive but guarantees per-segment language detection
