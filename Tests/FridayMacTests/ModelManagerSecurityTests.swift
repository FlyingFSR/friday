import Foundation
import Testing
@testable import FridayMac

struct ModelManagerSecurityTests {
  @Test
  func checksumMismatchFailsInstallAndLeavesNoFileBehind() async throws {
    let env = try SecurityTestEnvironment()
    defer { env.tearDown() }

    let session = FileServingDownloadSession(root: env.root, files: ["weights.safetensors": Data("tampered".utf8)])
    let manager = env.makeManager(
      files: [ModelFile(name: "weights.safetensors", sizeBytes: 8, sha256: String(repeating: "0", count: 64))],
      session: session
    )

    await #expect(throws: Error.self) {
      try await manager.ensureModelInstalled(.qwen3ASR)
    }

    let destination = env.modelsDirectory
      .appendingPathComponent(ModelTier.qwen3ASR.rawValue)
      .appendingPathComponent("weights.safetensors")
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    #expect(await manager.isInstalled(.qwen3ASR) == false)
  }

  @Test
  func downloadsEveryFileFromPinnedBaseAndVerifiesIt() async throws {
    let env = try SecurityTestEnvironment()
    defer { env.tearDown() }

    let config = Data("{\"a\":1}".utf8)
    let weights = Data("weights".utf8)
    let session = FileServingDownloadSession(
      root: env.root,
      files: ["config.json": config, "weights.safetensors": weights]
    )
    let manager = env.makeManager(
      files: [
        ModelFile(name: "config.json", sizeBytes: Int64(config.count), sha256: sha256Hex(config)),
        ModelFile(name: "weights.safetensors", sizeBytes: Int64(weights.count), sha256: sha256Hex(weights)),
      ],
      session: session
    )

    let directory = try await manager.ensureModelInstalled(.qwen3ASR)

    #expect(try Data(contentsOf: directory.appendingPathComponent("config.json")) == config)
    #expect(try Data(contentsOf: directory.appendingPathComponent("weights.safetensors")) == weights)
    #expect(session.requested.map(\.absoluteString).sorted() == [
      "https://example.com/pinned/config.json",
      "https://example.com/pinned/weights.safetensors",
    ])
  }

  @Test
  func invalidPinnedHashIsRejectedBeforeDownload() async throws {
    let env = try SecurityTestEnvironment()
    defer { env.tearDown() }

    let manager = env.makeManager(
      files: [ModelFile(name: "weights.safetensors", sizeBytes: 1, sha256: "UNVERIFIED")],
      session: FileServingDownloadSession(root: env.root, files: [:])
    )

    do {
      _ = try await manager.ensureModelInstalled(.qwen3ASR)
      Issue.record("Expected model checksum validation error.")
    } catch let error as FridayError {
      switch error {
      case .modelChecksumUnavailable(let model):
        #expect(model == ModelTier.qwen3ASR.rawValue)
      default:
        Issue.record("Unexpected error: \(error.localizedDescription)")
      }
    } catch {
      Issue.record("Unexpected error: \(error.localizedDescription)")
    }
  }
}

private struct SecurityTestEnvironment {
  let root: URL
  let modelsDirectory: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("friday-model-test-\(UUID().uuidString)", isDirectory: true)
    modelsDirectory = root.appendingPathComponent("models", isDirectory: true)
    try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
  }

  func makeManager(files: [ModelFile], session: any ModelDownloadSession) -> ModelManager {
    ModelManager(
      settingsStore: MockSettingsStoreForModelManager(),
      modelsDirectory: modelsDirectory,
      fileManager: .default,
      modelCatalog: [.qwen3ASR: ModelDescriptor(
        id: .qwen3ASR, displayName: "Qwen3-ASR 1.7B", approxSizeMB: 1, quality: "accurate",
        baseURL: "https://example.com/pinned", files: files
      )],
      downloadSession: session,
      resourceRootURL: nil
    )
  }

  func tearDown() {
    try? FileManager.default.removeItem(at: root)
  }
}

/// Serves each requested file name from memory by writing it to a fresh temporary file, the way
/// URLSession hands over a finished download.
private final class FileServingDownloadSession: ModelDownloadSession, @unchecked Sendable {
  let root: URL
  let files: [String: Data]
  private(set) var requested: [URL] = []

  init(root: URL, files: [String: Data]) {
    self.root = root
    self.files = files
  }

  func download(from url: URL) async throws -> (URL, URLResponse) {
    requested.append(url)
    guard let data = files[url.lastPathComponent] else {
      throw FridayError.modelDownloadFailed("not served: \(url.lastPathComponent)")
    }
    let temp = root.appendingPathComponent(UUID().uuidString)
    try data.write(to: temp)
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (temp, response)
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
