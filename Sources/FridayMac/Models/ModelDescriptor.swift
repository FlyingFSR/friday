import Foundation

struct ModelDescriptor: Codable, Identifiable {
  let id: ModelTier
  let displayName: String
  let approxSizeMB: Int
  let quality: String
  let downloadURL: String
  let sha256: String
}

enum ModelCatalog {
  static let all: [ModelTier: ModelDescriptor] = [
    .base: ModelDescriptor(
      id: .base,
      displayName: "Base",
      approxSizeMB: 70,
      quality: "fast",
      downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
      sha256: "UNVERIFIED"
    ),
    .small: ModelDescriptor(
      id: .small,
      displayName: "Small",
      approxSizeMB: 220,
      quality: "balanced",
      downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
      sha256: "UNVERIFIED"
    ),
    .medium: ModelDescriptor(
      id: .medium,
      displayName: "Medium",
      approxSizeMB: 800,
      quality: "accurate",
      downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
      sha256: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208"
    ),
    .largeV3: ModelDescriptor(
      id: .largeV3,
      displayName: "Large v3",
      approxSizeMB: 1600,
      quality: "best",
      downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
      sha256: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"
    )
  ]
}
