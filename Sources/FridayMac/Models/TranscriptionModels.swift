import Foundation

struct TranscriptionRequest {
  let wavPath: String
  let model: ModelTier
  let language: String
  let recordingDuration: TimeInterval
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

enum TranscriptionFailureKind: String {
  case chunkingFailed
  case chunkRetryFailed
  case fallbackBudgetExceeded
  case singlePassFailed
  case cancelled
  case unknown
}

struct TranscriptionFailure: Error {
  let kind: TranscriptionFailureKind
  let reason: String
  let artifactPaths: [String]
  let diagnostics: [String]

  init(
    kind: TranscriptionFailureKind = .unknown,
    reason: String,
    artifactPaths: [String] = [],
    diagnostics: [String] = []
  ) {
    self.kind = kind
    self.reason = reason
    self.artifactPaths = artifactPaths
    self.diagnostics = diagnostics
  }
}
