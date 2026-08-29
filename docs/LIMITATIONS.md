# Known Limitations — full detail

Friday is early software. The README carries a short version of this list; this
page is the unabridged one, with the reasoning and the measurements behind each
entry. Nothing here is a bug report waiting to be filed — these are current,
deliberate states of the project.

## Mixed-language edge cases

The whole recording is still decoded in a single pass with one auto-detected
language. 0.4.0 fixed the two failure modes this caused — Chinese sentences
inside English speech being dropped, and English passages being translated into
Chinese — but a recovered Chinese insertion can still come back with character
errors, and long Chinese narration can leave a few traditional characters in the
output, since Friday has no simplified/traditional normalization layer. See the
0.4.0 section of [CHANGELOG.md](../CHANGELOG.md) and
[docs/language-detection-findings-2026-08.md](language-detection-findings-2026-08.md)
for the measurements and the remaining costs.

The 0.4.0 evaluation ran on 21 samples recorded by the maintainer, in one
environment, with a single speaker. It measures a real change to a real failure
mode; it is not a general benchmark, and your voice, accent, room, and mix of
languages may not behave the way that set did.

## No terminal punctuation

In smart cleanup (the default), Friday deliberately strips a sentence-ending
period or question mark from the end of an utterance: a mark the model produced
is a guess about your intent, and a wrong guess is worse than none. Punctuation
inside the utterance is preserved.

If you dictate an explicit 句号 command and the model transcribes it as such, it
is treated as an instruction and survives, without doubling a mark the model had
already placed in front of it. But whisper does not reliably hear the command
word itself, so this is not a dependable escape hatch — do not lean on it.

## VAD is off by default

Per-segment voice-activity detection is implemented end to end but disabled while
its accuracy is validated, so the current path is a single-pass transcription of
the whole recording. The Silero VAD model is only downloaded if VAD is enabled.
[VAD_CHANGELOG.md](VAD_CHANGELOG.md) has the design history.

## Unsigned builds

Release zips are not yet signed or notarized, so the first launch needs the
**Privacy & Security** -> **Security** -> **Open Anyway** flow to get past
Gatekeeper. Signed and notarized builds are planned; the tooling for them is
already in the repo (`scripts/release-signed-notarized-dmg.sh`), it is the
developer account side that is not done.

## Apple Silicon only

macOS 13 or later on Apple Silicon. There is no Intel build.

## Single model: Medium

Friday ships only the Medium model. Earlier builds also offered Large v3 and
Turbo (`large-v3-turbo`); both were retired because Turbo could intermittently
drop short mid-sentence segments, and Medium proved the most reliable in everyday
use. Upgrading users are migrated to Medium automatically and the old weight
files are deleted to reclaim disk space.

## Opinionated text cleanup

Friday currently rewrites words that sound like AI coding tools — a standalone
"cloud"/"claud" becomes "Claude", and "codec"/"cortex"/"code x" become "Codex" —
in **all** cleanup modes, with no off switch yet.

As of 0.4.0 the same applies to Whisper, macOS, ChatGPT and OpenAI, and to a few
of the maintainer's own terms — which means the ordinary English words
"sol"/"sole"/"soles"/"soul"/"souls" all become "Sol", "fable"/"fables" become
"Fable", and "whisper"/"whispers" become "Whisper" (bare "whisper" is a
casing-only rewrite; `whisper.cpp` and `whisper-server` are left alone). If you
dictate those words in their ordinary sense, they will be replaced.

Friday also strips runs of Korean (Hangul) and Japanese kana from results as
whisper hallucination artifacts, so it is currently unsuitable for dictating
Japanese or Korean.

Both behaviors reflect the primary maintainer's daily Chinese/English workflow. A
user-configurable vocabulary list is planned. If the aggressive rewrites start
hurting ordinary English in practice, the intended order for narrowing them is
sole/soul first, then whispers, then codec/cortex.
