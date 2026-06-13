import CryptoKit
import Foundation
import Testing
@testable import FridayMac

/// `ensureModelInstalled` runs on every transcription, and a full SHA256 of a
/// ~1.5 GB model costs ~0.8s. Within one launch, a model verified once must not
/// be re-hashed: the checksum exists to catch bad downloads/tampered installs,
/// not to re-audit a file whisper-server has already loaded into memory.
struct ModelManagerChecksumCacheTests {
  @Test
  func repeatEnsureDoesNotRehashVerifiedModel() async throws {
    let env = try TestEnvironment()
    defer { env.tearDown() }

    let modelBytes = Data("valid-model-bytes".utf8)
    try modelBytes.write(to: env.modelURL)

    let manager = env.makeManager(sha256: Self.sha256Hex(modelBytes))

    _ = try await manager.ensureModelInstalled(.medium)

    // Corrupt the on-disk file. A re-hash would detect the mismatch, delete the
    // file, and hit the failing download session; a cached verification trusts
    // the launch-scoped result and returns immediately.
    let corruptedBytes = Data("corrupted-after-verification".utf8)
    try corruptedBytes.write(to: env.modelURL)

    let url = try await manager.ensureModelInstalled(.medium)

    #expect(url == env.modelURL)
    #expect(try Data(contentsOf: env.modelURL) == corruptedBytes)
  }

  @Test
  func removeModelClearsVerificationCache() async throws {
    let env = try TestEnvironment()
    defer { env.tearDown() }

    let modelBytes = Data("valid-model-bytes".utf8)
    try modelBytes.write(to: env.modelURL)

    let manager = env.makeManager(sha256: Self.sha256Hex(modelBytes))

    _ = try await manager.ensureModelInstalled(.medium)
    _ = try await manager.removeModel(.medium)

    // A new file at the same path after removal must be verified from scratch.
    try Data("tampered-replacement".utf8).write(to: env.modelURL)

    await #expect(throws: Error.self) {
      try await manager.ensureModelInstalled(.medium)
    }
  }

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private struct TestEnvironment {
  let fileManager = FileManager.default
  let root: URL
  let modelsDirectory: URL
  let modelURL: URL

  init() throws {
    root = fileManager.temporaryDirectory
      .appendingPathComponent("friday-checksum-cache-test-\(UUID().uuidString)", isDirectory: true)
    modelsDirectory = root.appendingPathComponent("models", isDirectory: true)
    try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    modelURL = modelsDirectory.appendingPathComponent("ggml-medium.bin")
  }

  func makeManager(sha256: String) -> ModelManager {
    let descriptor = ModelDescriptor(
      id: .medium,
      displayName: "Medium",
      approxSizeMB: 800,
      quality: "accurate",
      downloadURL: "https://example.com/ggml-medium.bin",
      sha256: sha256
    )
    return ModelManager(
      settingsStore: FailingDownloadSettingsStore(),
      modelsDirectory: modelsDirectory,
      fileManager: fileManager,
      modelCatalog: [.medium: descriptor],
      downloadSession: FailingModelDownloadSession(),
      resourceRootURL: nil
    )
  }

  func tearDown() {
    try? fileManager.removeItem(at: root)
  }
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
