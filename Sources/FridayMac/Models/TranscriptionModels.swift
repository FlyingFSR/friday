import Foundation

struct TranscriptionRequest {
  let wavPath: String
  let model: ModelTier
  let language: String
}

enum DetectedLanguage: String, Codable {
  case zh
  case en
  case mixed
  case unknown
}

struct TranscriptionResult {
  let text: String
  let detectedLanguage: DetectedLanguage
  let durationMs: Int
  let artifactPaths: [String]
  let diagnostics: [String]

  init(
    text: String,
    detectedLanguage: DetectedLanguage,
    durationMs: Int,
    artifactPaths: [String] = [],
    diagnostics: [String] = []
  ) {
    self.text = text
    self.detectedLanguage = detectedLanguage
    self.durationMs = durationMs
    self.artifactPaths = artifactPaths
    self.diagnostics = diagnostics
  }
}

struct TranscriptionFailure: Error {
  let reason: String
  let artifactPaths: [String]
  let diagnostics: [String]

  init(
    reason: String,
    artifactPaths: [String] = [],
    diagnostics: [String] = []
  ) {
    self.reason = reason
    self.artifactPaths = artifactPaths
    self.diagnostics = diagnostics
  }
}
