# Known Limitations — full detail

Friday is early software. The README carries a short version of this list; this
page is the unabridged one, with the reasoning and the measurements behind each
entry. Nothing here is a bug report waiting to be filed — these are current,
deliberate states of the project.

## Mixed-language edge cases

0.5.0 replaced whisper.cpp with Qwen3-ASR. Whisper detected one language for the
whole recording, which is what made it drop the second sentence of a short
Chinese-then-English recording; Qwen3-ASR is always told the main language
(Chinese, unless you choose English) and still writes English sentences in
English. On 50 short "one sentence Chinese, one sentence English" recordings,
every second sentence survived and none was translated. Left to detect the
language itself, Qwen3-ASR translated Chinese inside mixed dictation into
English, which is why the language is never left on automatic.

All of this was measured on recordings by the maintainer, in one quiet room, with
a single speaker (91 recordings across the evaluations). It measures real changes
to real failure modes; it is not a general benchmark, and your voice, accent,
room, and mix of languages may not behave the way that set did.

Friday gives the model a short list of names as hot words (Claude, Codex,
Qwen…). Rarely, a similar-sounding word is written as one of them: in the 41
evaluation recordings, "Cursor" became "Claude" once.

## No terminal punctuation

In smart cleanup (the default), Friday deliberately strips a sentence-ending
period or question mark from the end of an utterance: a mark the model produced
is a guess about your intent, and a wrong guess is worse than none. Punctuation
inside the utterance is preserved.

If you dictate an explicit 句号 command and the model transcribes it as such, it
is treated as an instruction and survives, without doubling a mark the model had
already placed in front of it. But the model does not reliably hear the command
word itself, so this is not a dependable escape hatch — do not lean on it.

## Unsigned builds

Release zips are not yet signed or notarized, so the first launch needs the
**Privacy & Security** -> **Security** -> **Open Anyway** flow to get past
Gatekeeper. Signed and notarized builds are planned; the tooling for them is
already in the repo (`scripts/release-signed-notarized-dmg.sh`), it is the
developer account side that is not done.

## Apple Silicon only

macOS 14 or later on Apple Silicon (MLX requires it). There is no Intel build.

## Single model, and memory

Friday ships one model: Qwen3-ASR 1.7B, 8-bit, about 2.2 GB to download. It stays
loaded while Friday runs, at about 2.3 GB of resident memory and more while a
long recording is being transcribed; 0.4's whisper-server used about 1 GB.
Earlier Whisper-based builds offered Medium, Large v3 and Turbo; none of them is
used by 0.5. A Whisper Medium file left over from 0.4 is not deleted, so going
back to 0.4 needs no download.

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

Friday also strips runs of Korean (Hangul) and Japanese kana from results, a
filter kept from the Whisper era when they were hallucination artifacts, so it
is currently unsuitable for dictating Japanese or Korean.

Both behaviors reflect the primary maintainer's daily Chinese/English workflow. A
user-configurable vocabulary list is planned. If the aggressive rewrites start
hurting ordinary English in practice, the intended order for narrowing them is
sole/soul first, then whispers, then codec/cortex.
