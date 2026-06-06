# Security Policy

Friday is a local-first macOS voice-input app. Security and privacy issues are
taken seriously, especially anything involving audio capture, transcript
handling, permissions, paste behavior, model downloads, or bundled native
runtime files.

## Supported Versions

Only the latest public release is actively supported for security fixes.
Download it from:

https://github.com/FlyingFSR/friday/releases/latest

## Reporting a Vulnerability

Please avoid posting exploit details publicly.

If GitHub private vulnerability reporting is available for this repository, use
that path. If not, open a minimal public issue saying you have a security report
and include only the affected area, not reproduction details or sensitive data.

Useful report details:

- Friday version
- macOS version and Mac model
- Affected component or workflow
- Impact
- Minimal reproduction steps, if safe to share privately

The maintainer will acknowledge credible reports as soon as possible and will
prioritize fixes that could expose private audio, transcripts, permissions, or
local files.

## Project Security Expectations

- Audio and transcripts should stay on the user's Mac unless a future feature is
  explicitly opt-in and clearly documented.
- Friday should not add telemetry, cloud transcription, or remote logging without
  a public design discussion.
- Paste behavior must respect secure input and protected contexts.
- Release packaging should keep bundled native binaries and libraries verifiable.
