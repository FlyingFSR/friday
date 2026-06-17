# Changelog

## 0.3.4 - 2026-06-17

### Models

- **Retired the Turbo model; Friday now ships Medium only.** In real use Turbo
  (`large-v3-turbo`) could intermittently drop short mid-sentence segments,
  while Medium proved consistently reliable. Turbo is removed from the menu and
  setup screens. On launch, any saved default still pointing at Turbo (or the
  older Large v3) is migrated to Medium, and the obsolete weight files are
  deleted to reclaim disk space.

### Interface

- The menu bar panel now shows the app version next to the Friday title.

## 0.3.3 - 2026-06-13

### Performance

- **Dictation is ~0.8s faster.** The full model checksum (1.4–1.6 GB SHA256)
  was being re-verified on every transcription. Checksums are still verified
  on download, install, and once per launch; within a running session the
  verified result is now cached, and removing a model invalidates its cache
  entry.

### Continuous integration

- Added a GitHub Actions workflow that builds the app and runs the full test
  suite on every push and pull request, with a status badge in the README.

### Documentation

- Known Limitations now discloses Friday's opinionated cleanup behaviors:
  brand-name normalization (e.g. "cloud" → "Claude", "codec" → "Codex") runs in
  all cleanup modes, and Korean/Japanese character runs are stripped as
  hallucination artifacts. A user-configurable vocabulary list is planned.

## 0.3.2 - 2026-06-11

### Reliability

- Unified model fallback routing so the app and `whisper-server` always agree
  on the installed transcription model to use. If the saved default is missing
  and only Turbo is installed, Friday now routes both paths to Turbo instead of
  letting one path drift back to Medium.
- Centralized CJK script detection across language detection, diagnostics,
  cleanup, and hallucination trimming so mixed Chinese/English behavior uses
  one shared definition of Chinese text.

### Project maintenance

- Added community-facing GitHub templates and support docs, plus the demo media
  used by the README.
- Added durable project closeout rules so useful Friday changes from earlier
  sessions are verified and committed instead of being left dangling.

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
