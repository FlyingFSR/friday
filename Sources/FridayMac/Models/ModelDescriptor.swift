import Foundation

struct ModelFile: Codable, Equatable {
  let name: String
  let sizeBytes: Int64
  let sha256: String
}

struct ModelDescriptor: Codable, Identifiable {
  let id: ModelTier
  let displayName: String
  let approxSizeMB: Int
  let quality: String
  /// Directory URL the files are fetched from, pinned to one revision.
  let baseURL: String
  let files: [ModelFile]
}

enum ModelCatalog {
  /// Qwen3-ASR 1.7B, 8-bit, in the mlx-qwen3-asr layout. The files are fetched from
  /// moona3k/mlx-qwen3-asr-1.7b-8bit at a pinned revision, but trust does not rest on that
  /// publisher: every checksum below was computed from our own 8-bit conversion of Alibaba's
  /// official Qwen/Qwen3-ASR-1.7B (revision 7278e1e), which came out byte-identical
  /// (docs/qwen3-asr-swift-port-2026-10.md). A file that does not match is rejected.
  static let qwen3ASR = ModelDescriptor(
    id: .qwen3ASR,
    displayName: "Qwen3-ASR 1.7B",
    approxSizeMB: 2180,
    quality: "accurate",
    baseURL: "https://huggingface.co/moona3k/mlx-qwen3-asr-1.7b-8bit/resolve/22c8abe6a6772122dda5905967d7496d1d3e8dd2",
    files: [
      ModelFile(name: "config.json", sizeBytes: 6194,
                sha256: "2e74a751548b8ad7d7526d29365ad8144c345d8b412b1152d25dc6698452712f"),
      ModelFile(name: "quantization_config.json", sizeBytes: 35,
                sha256: "964fe0bcf1c9cb41a0a66616e64c2bfcf93bd5581f3abd869b0e72d3dbc66154"),
      ModelFile(name: "tokenizer_config.json", sizeBytes: 12487,
                sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"),
      ModelFile(name: "vocab.json", sizeBytes: 2_776_833,
                sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
      ModelFile(name: "merges.txt", sizeBytes: 1_671_853,
                sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
      ModelFile(name: "weights.safetensors", sizeBytes: 2_169_903_389,
                sha256: "eba2bdb1ec74f5df99345f9f81492ba551f6b072eedfef564b353ef0dde90bb8"),
    ]
  )

  static let all: [ModelTier: ModelDescriptor] = [.qwen3ASR: qwen3ASR]
}
