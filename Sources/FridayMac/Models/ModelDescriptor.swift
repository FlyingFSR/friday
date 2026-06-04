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
      approxSizeMB: 1530,
      quality: "accurate",
      downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
      sha256: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208"
    ),
    .turbo: ModelDescriptor(
      id: .turbo,
      displayName: "Turbo",
      approxSizeMB: 1550,
      quality: "best",
      downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
      sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
    )
  ]
}
