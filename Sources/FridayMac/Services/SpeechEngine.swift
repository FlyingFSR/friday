import Foundation
import Qwen3ASR

/// Owns the in-process Qwen3-ASR model. The model is loaded once (about 2.3 GB resident) and
/// kept for the life of the app; the actor serializes access because the model is not
/// thread-safe.
actor SpeechEngine {
  private var model: Qwen3ASRModel?
  private var loadedDirectory: URL?

  var isLoaded: Bool { model != nil }

  /// Loads the model from `directory` unless it is already loaded from there, then runs one
  /// second of silence through it so the first real dictation does not pay for kernel setup.
  func load(modelDirectory directory: URL) throws {
    if model != nil, loadedDirectory == directory {
      return
    }
    model = nil
    loadedDirectory = nil
    let loaded = try Qwen3ASRModel(directory: directory)
    _ = try loaded.transcribe([Float](repeating: 0, count: 16_000), language: "Chinese")
    model = loaded
    loadedDirectory = directory
  }

  /// 16 kHz mono samples in [-1, 1). Checks task cancellation between decoding steps.
  func transcribe(samples: [Float], language: String, context: String) throws -> TranscriptionOutput {
    guard let model else {
      throw FridayError.speechEngineNotReady
    }
    return try model.transcribe(samples, language: language, context: context) {
      Task.isCancelled
    }
  }
}
