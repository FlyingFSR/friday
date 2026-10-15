# Qwen3ASR module: provenance

On-device Qwen3-ASR inference for Friday. Friday itself is MIT-licensed; this
module contains code derived from Apache-2.0 projects, whose license text is in
`LICENSE-Apache-2.0` next to this file.

- soniqo/speech-swift, commit cbcdfc6be5e723952d29ab6e32af5e22ad8e70fa
  (2026-10-07): Sources/Qwen3ASR, Sources/AudioCommon/Tokenizer.swift and
  Sources/MLXCommon. Copyright the speech-swift authors.
- Alibaba qwen-asr 0.0.6 (Qwen team): audio chunking, repetition clean-up and
  output parsing from qwen_asr/inference/utils.py, translated in
  `OfficialWorkflow.swift`.
- mlx-qwen3-asr 0.4.4 (Daniel Moon): used as the numerical reference while
  porting; the byte-level BPE in `Tokenizer.swift` follows its implementation.

Every derived file starts with a header naming its source and listing Friday's
modifications (2026-10-12). The review and the parity tests behind them are in
`docs/qwen3-asr-swift-port-2026-10.md`.

Runtime dependency: Apple ml-explore/mlx-swift 0.32.3 (MIT). Its Metal shader
library must match the bundled MLX core (0.32.2); see
`scripts/fetch-mlx-metallib.sh`.
