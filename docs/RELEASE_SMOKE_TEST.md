# Release Smoke Test

Friday's highest-risk behavior depends on a real macOS environment (permissions,
hotkey capture, whisper runtime, paste), which unit tests can't cover. Run this
checklist on a **clean** Apple Silicon Mac — ideally a fresh user account with no
Homebrew whisper.cpp on `PATH` — before publishing a release.

Tick every box. If anything fails, do not publish.

## 0. Package sanity (can run on the build machine)

- [ ] `bash scripts/build-local-app.sh` completes without error.
- [ ] `dist/Friday.app/Contents/MacOS/whisper-server` exists and is executable.
- [ ] `otool -L dist/Friday.app/Contents/MacOS/whisper-server` shows **no**
      `@rpath/lib{whisper,ggml}` lines (all whisper libs resolve via
      `@executable_path/../Frameworks`). The build script's packaging guards also
      check both of these and fail the build otherwise.
- [ ] `codesign --verify --deep --strict --verbose=2 dist/Friday.app` passes.
      This catches broken nested-code signatures for `whisper-server` and the
      bundled `libwhisper` / `libggml` libraries before a release asset ships.
- [ ] The release zip unzips to a `Friday.app` that opens in Finder.
- [ ] After unzipping the release zip, run the same `codesign --verify --deep
      --strict --verbose=2 /path/to/Friday.app` check on the unzipped app.

A quick standalone check that the bundled runtime is self-sufficient (no Homebrew):

```bash
BIN="dist/Friday.app/Contents/MacOS/whisper-server"
MODEL="$HOME/Library/Application Support/Friday/models/ggml-medium.bin"
env -i HOME="$HOME" PATH="/usr/bin:/bin" "$BIN" -m "$MODEL" \
  --host 127.0.0.1 --port 8190 --no-timestamps &
sleep 8 && curl -s http://127.0.0.1:8190/health    # expect HTTP 200
kill %1
```

## 1. Fresh install

- [ ] Download the published zip on a clean Apple Silicon Mac (macOS 13+).
- [ ] Unzip and move `Friday.app` to `/Applications`.
- [ ] First launch of the **unsigned** build: click **Done** on the Gatekeeper
      warning, then use **System Settings** -> **Privacy & Security** ->
      **Security** -> **Open Anyway**, confirm again, and enter the
      administrator password.
- [ ] App launches without a crash.

## 2. Menu bar & onboarding

- [ ] The menu bar icon appears **immediately** on launch.
- [ ] Onboarding/setup window appears when permissions or the model are missing.

## 3. Permissions

- [ ] Microphone prompt/flow works and reflects granted state.
- [ ] Accessibility flow works (required for paste).
- [ ] Input Monitoring flow works (required for the global hotkey).
- [ ] After granting all three, onboarding no longer blocks use.
- [ ] If the hotkey does not fire immediately after granting Input Monitoring,
      quit and reopen Friday once, then retest before calling it a failure.

## 4. Model

- [ ] Medium model installs (download in onboarding) or a bundled model is
      detected, and the app reports it as ready.
- [ ] Model policy shows a realistic download size: Medium ~1.5 GB.
- [ ] whisper-server starts after the model is ready (no "whisper-server not
      found / failed to start" error).

## 5. Core dictation

- [ ] Open a clean TextEdit / Notes window.
- [ ] Use a physical keyboard with a real **Right Command** key, and confirm the
      Mac has a connected/selected microphone input. The macOS virtual keyboard
      is not a reliable hotkey smoke-test source.
- [ ] Hold **Right Command**, speak one short English sentence, release -> text
      is inserted at the cursor.
- [ ] Repeat with one short Chinese sentence.
- [ ] Repeat with one mixed sentence (e.g. "今天用 Claude 写一个 React component").
- [ ] No spurious trailing "Thank you / Bye" or stray Korean/Japanese characters.

## 6. Paste safety

- [ ] With clipboard-restore enabled, your previous clipboard contents are
      restored after a dictation.
- [ ] Focus a password field (e.g. login screen, 1Password) and try to dictate →
      paste is **blocked / safely handled** (secure-input guard).

## 7. Diagnostics

- [ ] When something fails (e.g. deny a permission on purpose), the error surfaced
      to the user is understandable, not a silent no-op.

## 8. Version

- [ ] The version shown in-app matches the release tag (e.g. `0.3.0`, not the
      default build-script fallback). The publish script exports `FRIDAY_SHORT_VERSION` from the
      tag; verify it took effect.

---

Record the macOS version, Mac model, and anything that needed a workaround in the
release notes or the tracking issue
([#2](https://github.com/FlyingFSR/friday/issues/2)).
