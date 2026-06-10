# Changelog

## 0.3.1 - 2026-06-05

### Maintainer field note - 2026-06-10

- After several days of real daily use on the current release, Friday has been
  stable and handy for the maintainer's own push-to-talk workflow, with no
  blocking issues observed during that period. This is still early maintainer
  feedback rather than a broad compatibility claim, but it is a useful signal
  that the 0.3.x reliability work is holding up in normal use.

### Reliability

- **whisper-server now recovers if it dies mid-session.** `isReady` was set once at
  startup and never re-checked, so if the transcription engine crashed after boot,
  every later dictation failed until Friday was relaunched. The pipeline now detects
  a dropped connection, restarts the server once, and retries the transcription a
  single time. Timeouts and HTTP errors deliberately do **not** trigger a restart
  (the server is alive, just slow), so a working transcription is never killed.

### Internal cleanup

- Removed dead transcription routing/failure scaffolding left over from the
  rolled-back chunked-transcription experiment (the unused per-request
  `recordingDuration`, the no-op routing wrapper, and the unreachable
  `TranscriptionFailureKind` cases).
- Removed the unused `hotkey` setting (the hotkey is fixed to Right Command) and
  renamed a mis-named test file.

## 0.3.0 - 2026-06-04

### Transcription models

- **Replaced Large v3 with Turbo (`large-v3-turbo`).** Turbo offers accuracy close
  to Large v3 on mixed Chinese/English dictation at much higher speed and lower
  memory, which makes it a better default for push-to-talk. The model picker now
  offers **Medium** and **Turbo**.
- **Automatic migration.** On first launch after upgrading, a saved default of
  `large-v3` is migrated to Turbo (or Medium if Turbo isn't installed yet), and the
  obsolete ~3 GB `ggml-large-v3.bin` weight file is deleted to reclaim disk space.

### Fixes

- **Switching the default model now restarts whisper-server immediately.**
  Previously, choosing a different model in the menu only updated settings; the
  long-lived server kept the previously loaded model until the app was relaunched,
  so the change silently had no effect.

### Internal cleanup

- Removed the never-invoked background Large-v3 auto-install machinery (and its
  disk-space/backoff bookkeeping).
- Removed the large↔medium "quality fallback" routing. It could not work against
  the single-model whisper-server — every `/inference` request targets the one
  model the server was started with, regardless of the per-request model field — so
  the fallback re-ran the same model against itself.
- Removed dead CLI-era code (`buildWhisperArguments` / `AutoDecodingMode`) and the
  orphaned ffmpeg-based silence-segmentation code that was never wired into the
  request path.
