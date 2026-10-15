# Release Smoke Test

Friday's highest-risk behavior depends on a real macOS environment (permissions,
hotkey capture, the MLX runtime, paste), which unit tests can't cover. Run this
checklist on a **clean** Apple Silicon Mac — ideally a fresh user account — before
publishing a release.

Tick every box. If anything fails, do not publish.

## 0. Package sanity (can run on the build machine)

- [ ] `bash scripts/build-local-app.sh` completes without error.
- [ ] `dist/Friday.app/Contents/Resources/mlx-swift_Cmlx.bundle/default.metallib`
      exists and is not empty. MLX loads its GPU shaders from this file; without
      it the first dictation fails. The build script's packaging guard also
      checks this and fails the build otherwise.
- [ ] `codesign --verify --deep --strict --verbose=2 dist/Friday.app` passes.
- [ ] The release zip unzips to a `Friday.app` that opens in Finder.
- [ ] After unzipping the release zip, run the same `codesign --verify --deep
      --strict --verbose=2 /path/to/Friday.app` check on the unzipped app.

## 1. Fresh install

- [ ] Download the published zip on a clean Apple Silicon Mac (macOS 14+).
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

- [ ] The Qwen3-ASR 1.7B model installs (download in onboarding, about 2.2 GB)
      and the app reports it as ready.
- [ ] The first dictation after launch succeeds (no "Failed to load the default
      metallib" or model-load error).

## 5. Core dictation

- [ ] Open a clean TextEdit / Notes window.
- [ ] Use a physical keyboard with a real **Right Command** key, and confirm the
      Mac has a connected/selected microphone input. The macOS virtual keyboard
      is not a reliable hotkey smoke-test source.
- [ ] Hold **Right Command**, speak one short English sentence, release -> text
      is inserted at the cursor.
- [ ] Repeat with one short Chinese sentence.
- [ ] Repeat with one mixed sentence (e.g. "今天用 Claude 写一个 React component").
- [ ] Say one short Chinese sentence, pause briefly, then one short English
      sentence (e.g. "我觉得这个方案还行。The quick fix worked.") -> **both**
      sentences appear, each in its own language. Repeat in the other order.
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
