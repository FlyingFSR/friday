import Foundation
import Testing
@testable import FridayMac

struct ModelManagerSecurityTests {
  @Test
  func checksumMismatchFailsInstallAndCleansDestinationFile() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("friday-model-test-\(UUID().uuidString)", isDirectory: true)
    let modelsDirectory = root.appendingPathComponent("models", isDirectory: true)
    try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    defer {
      try? fileManager.removeItem(at: root)
    }

    let downloadedFile = root.appendingPathComponent("downloaded-medium.bin")
    try Data("tampered".utf8).write(to: downloadedFile)

    let response = try #require(
      HTTPURLResponse(
        url: URL(string: "https://example.com/ggml-medium.bin")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )
    )

    let session = MockModelDownloadSession(result: .success((downloadedFile, response)))
    let descriptor = ModelDescriptor(
      id: .medium,
      displayName: "Medium",
      approxSizeMB: 800,
      quality: "accurate",
      downloadURL: "https://example.com/ggml-medium.bin",
      sha256: String(repeating: "0", count: 64)
    )

    let manager = ModelManager(
      settingsStore: MockSettingsStoreForModelManager(),
      modelsDirectory: modelsDirectory,
      fileManager: fileManager,
      modelCatalog: [.medium: descriptor],
      downloadSession: session,
      resourceRootURL: nil
    )

    await #expect(throws: Error.self) {
      try await manager.ensureModelInstalled(.medium)
    }

    let destinationPath = modelsDirectory.appendingPathComponent("ggml-medium.bin").path
    #expect(!fileManager.fileExists(atPath: destinationPath))
  }

  @Test
  func invalidPinnedHashIsRejectedBeforeDownload() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("friday-model-test-\(UUID().uuidString)", isDirectory: true)
    let modelsDirectory = root.appendingPathComponent("models", isDirectory: true)
    try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    defer {
      try? fileManager.removeItem(at: root)
    }

    let descriptor = ModelDescriptor(
      id: .largeV3,
      displayName: "Large v3",
      approxSizeMB: 1600,
      quality: "best",
      downloadURL: "https://example.com/ggml-large-v3.bin",
      sha256: "UNVERIFIED"
    )

    let manager = ModelManager(
      settingsStore: MockSettingsStoreForModelManager(),
      modelsDirectory: modelsDirectory,
      fileManager: fileManager,
      modelCatalog: [.largeV3: descriptor],
      downloadSession: MockModelDownloadSession(result: .failure(FridayError.modelDownloadFailed("should not download"))),
      resourceRootURL: nil
    )

    do {
      _ = try await manager.ensureModelInstalled(.largeV3)
      Issue.record("Expected model checksum validation error.")
    } catch let error as FridayError {
      switch error {
      case .modelChecksumUnavailable(let model):
        #expect(model == descriptor.id.rawValue)
      default:
        Issue.record("Unexpected error: \(error.localizedDescription)")
      }
    } catch {
      Issue.record("Unexpected error: \(error.localizedDescription)")
    }
  }
}

private final class MockModelDownloadSession: ModelDownloadSession {
  let result: Result<(URL, URLResponse), Error>

  init(result: Result<(URL, URLResponse), Error>) {
    self.result = result
  }

  func download(from url: URL) async throws -> (URL, URLResponse) {
    try result.get()
  }
}

private final class MockSettingsStoreForModelManager: SettingsStoreControlling {
  var current = FridaySettings.default

  func load() async -> FridaySettings {
    current
  }

  func update(_ mutate: (inout FridaySettings) -> Void) async -> FridaySettings {
    mutate(&current)
    return current
  }
}
