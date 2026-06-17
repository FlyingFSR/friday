# Mixed-Language Dictation — Manual Eval

A repeatable way to measure how well Friday preserves **frequent Chinese/English
switching** in a single recording, and whether any spoken content is *dropped*
(the serious failure) versus merely needing punctuation/casing cleanup (minor).
Tracks [issue #4](https://github.com/FlyingFSR/friday/issues/4).

This needs a real human voice, so it is a manual checklist, not an automated test.

## Why dropped segments happen

The current path sends the whole recording to whisper-server in a single pass
with `-l auto`. Whisper detects language roughly once, so when one recording
switches languages many times, short segments in the "other" language can be
dropped or mistranscribed. VAD segmentation (which would shorten each chunk) is
implemented but disabled by default — see [VAD_CHANGELOG.md](../VAD_CHANGELOG.md).

## How to run

For each phrase below: open a clean TextEdit window, hold **Right Command**,
read the phrase **once at a natural pace**, release, and paste. Record the result
verbatim. Run the whole set on **Medium** (the model Friday ships).

Score each phrase:

- **PASS** — every bracketed key token (see below) appears, in order. Punctuation
  and casing differences are fine.
- **DROP** — one or more bracketed tokens are missing or replaced by the wrong
  language. Note exactly which.

## Test phrases

Key tokens that must survive are in `[brackets]`. Bracket markers are *not* spoken.

1. **Low switching (baseline).**
   今天我用 `[Claude]` 写了一个 `[React]` 组件。

2. **Brand names mid-Chinese.**
   我让 `[Codex]` review 这个 `[pull request]`,然后部署到 `[production]`。

3. **Rapid alternation (the hard case).**
   先 `[open]` 这个 `[file]`,再 `[run]` 一下 `[test]`,如果 `[fail]` 就 `[debug]`。

4. **English clause inside Chinese.**
   这个 `[function]` 的问题是 it `[silently]` `[drops]` the English `[segment]`,
   我们需要修一下。

5. **Numbers / tech terms.**
   把 `[Medium]` 的 `[latency]` 和 `[accuracy]` 都 `[benchmark]` 一下。

6. **Long English tail after Chinese.**
   我先解释一下背景,然后 `[here is the part that usually gets dropped because]`
   `[it is a long English sentence at the very end]`。

7. **Tech vocabulary burst.**
   用 `[Swift]` 写 `[macOS]` app,调 `[whisper.cpp]` 的 `[whisper-server]`,走
   `[HTTP]` `[inference]` 接口。

## Recording results

| # | Model | Result (verbatim) | Score | Dropped tokens |
|---|-------|-------------------|-------|----------------|
| 1 | Medium |  |  |  |
| 2 | Medium |  |  |  |
| … | … |  |  |  |

## What to do with the results

- Any **DROP** on phrases 1–2 is a regression — file/escalate immediately.
- DROPs concentrated on phrases 3, 4, 6 confirm the single-pass language-detection
  root cause; that is the signal for whether re-enabling VAD (or per-chunk
  decoding) is worth it.
- Paste the filled table into [issue #4](https://github.com/FlyingFSR/friday/issues/4)
  so the dropped-segment cases are tracked with concrete evidence.
