import CryptoKit
import Foundation
import Testing
@testable import FridayMac

/// `ensureModelInstalled` runs on every transcription, and hashing the 2.2 GB
/// weights costs about a second. Within one launch, a model verified once must
/// not be re-hashed: the checksum exists to catch bad downloads/tampered installs,
/// not to re-audit files the engine has already loaded into memory.
struct ModelManagerChecksumCacheTests {
  @Test
  func repeatEnsureDoesNotRehashVerifiedModel() async throws {
    let env = try TestEnvironment()
    defer { env.tearDown() }

    let modelBytes = Data("valid-model-bytes".utf8)
    try env.writeModelFile(modelBytes)
    let manager = env.makeManager(for: modelBytes)

    _ = try await manager.ensureModelInstalled(.qwen3ASR)

    // Corrupt the on-disk file (same size). A re-hash would detect the mismatch,
    // delete the file, and hit the failing download session; a cached verification
    // trusts the launch-scoped result and returns immediately.
    let corruptedBytes = Data("valid-model-BYTES".utf8)
    try env.writeModelFile(corruptedBytes)

    let url = try await manager.ensureModelInstalled(.qwen3ASR)

    #expect(url == env.modelDirectory)
    #expect(try Data(contentsOf: env.modelFileURL) == corruptedBytes)
  }

  @Test
  func removeModelClearsVerificationCache() async throws {
    let env = try TestEnvironment()
    defer { env.tearDown() }

    let modelBytes = Data("valid-model-bytes".utf8)
    try env.writeModelFile(modelBytes)
    let manager = env.makeManager(for: modelBytes)

    _ = try await manager.ensureModelInstalled(.qwen3ASR)
    #expect(try await manager.removeModel(.qwen3ASR))

    // A new file at the same path after removal must be verified from scratch.
    try env.writeModelFile(Data("tampered-replaceme".utf8))

    await #expect(throws: Error.self) {
      try await manager.ensureModelInstalled(.qwen3ASR)
    }
  }

  @Test
  func removingRetiredWhisperTierDeletesItsLegacyFileOnly() async throws {
    let env = try TestEnvironment()
    defer { env.tearDown() }

    let legacy = env.modelsDirectory.appendingPathComponent("ggml-large-v3.bin")
    try Data("old whisper".utf8).write(to: legacy)
    let medium = env.modelsDirectory.appendingPathComponent("ggml-medium.bin")
    try Data("kept for rollback".utf8).write(to: medium)
    let manager = env.makeManager(for: Data("x".utf8))

    #expect(try await manager.removeModel(.largeV3))
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    #expect(FileManager.default.fileExists(atPath: medium.path))
  }
}

private struct TestEnvironment {
  let fileManager = FileManager.default
  let root: URL
  let modelsDirectory: URL
  let modelDirectory: URL
  let modelFileURL: URL

  init() throws {
    root = fileManager.temporaryDirectory
      .appendingPathComponent("friday-checksum-cache-test-\(UUID().uuidString)", isDirectory: true)
    modelsDirectory = root.appendingPathComponent("models", isDirectory: true)
    modelDirectory = modelsDirectory.appendingPathComponent(ModelTier.qwen3ASR.rawValue, isDirectory: true)
    modelFileURL = modelDirectory.appendingPathComponent("weights.safetensors")
    try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
  }

  func writeModelFile(_ data: Data) throws {
    try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
    try data.write(to: modelFileURL)
  }

  func makeManager(for bytes: Data) -> ModelManager {
    let descriptor = ModelDescriptor(
      id: .qwen3ASR,
      displayName: "Qwen3-ASR 1.7B",
      approxSizeMB: 1,
      quality: "accurate",
      baseURL: "https://example.com/model",
      files: [ModelFile(name: "weights.safetensors", sizeBytes: Int64(bytes.count), sha256: sha256Hex(bytes))]
    )
    return ModelManager(
      settingsStore: FailingDownloadSettingsStore(),
      modelsDirectory: modelsDirectory,
      fileManager: fileManager,
      modelCatalog: [.qwen3ASR: descriptor],
      downloadSession: FailingModelDownloadSession(),
      resourceRootURL: nil
    )
  }

  func tearDown() {
    try? fileManager.removeItem(at: root)
  }
}

func sha256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private final class FailingModelDownloadSession: ModelDownloadSession {
  func download(from url: URL) async throws -> (URL, URLResponse) {
    throw FridayError.modelDownloadFailed("test session must not download")
  }
}

private final class FailingDownloadSettingsStore: SettingsStoreControlling {
  var current = FridaySettings.default

  func load() async -> FridaySettings {
    current
  }

  func update(_ mutate: (inout FridaySettings) -> Void) async -> FridaySettings {
    mutate(&current)
    return current
  }
}
