import CryptoKit
import Foundation

protocol ModelDownloadSession {
  func download(from url: URL) async throws -> (URL, URLResponse)
}

extension URLSession: ModelDownloadSession {
  func download(from url: URL) async throws -> (URL, URLResponse) {
    try await download(from: url, delegate: nil)
  }
}

actor ModelManager {
  private let settingsStore: any SettingsStoreControlling
  private let modelsDirectory: URL
  private let fileManager: FileManager
  private let modelCatalog: [ModelTier: ModelDescriptor]
  private let downloadSession: any ModelDownloadSession
  private let resourceRootURL: URL?

  private static let vadModelFilename = "ggml-silero-v6.2.0.bin"
  private static let vadModelDownloadURL = "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin"

  init(
    settingsStore: any SettingsStoreControlling,
    modelsDirectory: URL? = nil,
    fileManager: FileManager = .default,
    modelCatalog: [ModelTier: ModelDescriptor] = ModelCatalog.all,
    downloadSession: any ModelDownloadSession = URLSession.shared,
    resourceRootURL: URL? = Bundle.main.resourceURL
  ) {
    self.settingsStore = settingsStore
    self.fileManager = fileManager
    self.modelCatalog = modelCatalog
    self.downloadSession = downloadSession
    self.resourceRootURL = resourceRootURL

    if let modelsDirectory {
      self.modelsDirectory = modelsDirectory
    } else {
      let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      self.modelsDirectory = appSupport
        .appendingPathComponent("Friday", isDirectory: true)
        .appendingPathComponent("models", isDirectory: true)
    }
  }

  func descriptor(for tier: ModelTier) throws -> ModelDescriptor {
    guard let descriptor = modelCatalog[tier] else {
      throw FridayError.modelNotFound
    }
    return descriptor
  }

  func ensureModelInstalled(_ tier: ModelTier) async throws -> URL {
    try ensureModelDirectory()

    let descriptor = try descriptor(for: tier)
    guard shouldValidateHash(descriptor.sha256) else {
      throw FridayError.modelChecksumUnavailable(tier.rawValue)
    }

    let modelURL = modelFileURL(for: tier)
    if fileManager.fileExists(atPath: modelURL.path) {
      do {
        try verifyChecksum(of: modelURL, expected: descriptor.sha256)
        try await syncInstalledModelsWithSettings()
        return modelURL
      } catch {
        try? fileManager.removeItem(at: modelURL)
      }
    }

    if try copyBundledModelIfAvailable(tier, descriptor: descriptor, to: modelURL) {
      try await syncInstalledModelsWithSettings()
      return modelURL
    }

    guard let sourceURL = URL(string: descriptor.downloadURL) else {
      throw FridayError.modelNotFound
    }

    let (downloadedURL, response): (URL, URLResponse)
    do {
      (downloadedURL, response) = try await downloadSession.download(from: sourceURL)
    } catch {
      throw FridayError.modelDownloadFailed(error.localizedDescription)
    }
    defer {
      try? fileManager.removeItem(at: downloadedURL)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw FridayError.modelDownloadFailed("unexpected response type")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw FridayError.modelDownloadFailed("HTTP \(httpResponse.statusCode)")
    }

    guard try fileSize(at: downloadedURL) > 0 else {
      throw FridayError.modelDownloadFailed("downloaded model is empty")
    }

    do {
      try verifyChecksum(of: downloadedURL, expected: descriptor.sha256)
    } catch FridayError.transcriptionFailed {
      throw FridayError.modelDownloadFailed("model checksum mismatch")
    } catch {
      throw FridayError.modelDownloadFailed(error.localizedDescription)
    }

    if fileManager.fileExists(atPath: modelURL.path) {
      try fileManager.removeItem(at: modelURL)
    }

    try fileManager.moveItem(at: downloadedURL, to: modelURL)
    try await syncInstalledModelsWithSettings()
    return modelURL
  }

  func ensureVADModelInstalled() async throws -> URL {
    try ensureModelDirectory()

    let vadURL = modelsDirectory.appendingPathComponent(Self.vadModelFilename)
    if fileManager.fileExists(atPath: vadURL.path) {
      return vadURL
    }

    guard let sourceURL = URL(string: Self.vadModelDownloadURL) else {
      throw FridayError.modelDownloadFailed("invalid VAD model URL")
    }

    let (downloadedURL, response): (URL, URLResponse)
    do {
      (downloadedURL, response) = try await downloadSession.download(from: sourceURL)
    } catch {
      throw FridayError.modelDownloadFailed("VAD model: \(error.localizedDescription)")
    }
    defer {
      try? fileManager.removeItem(at: downloadedURL)
    }

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw FridayError.modelDownloadFailed("VAD model download failed")
    }

    guard try fileSize(at: downloadedURL) > 0 else {
      throw FridayError.modelDownloadFailed("downloaded VAD model is empty")
    }

    if fileManager.fileExists(atPath: vadURL.path) {
      try fileManager.removeItem(at: vadURL)
    }

    try fileManager.moveItem(at: downloadedURL, to: vadURL)
    return vadURL
  }

  func isInstalled(_ tier: ModelTier) -> Bool {
    fileManager.fileExists(atPath: modelFileURL(for: tier).path)
  }

  func installedModels() async -> [ModelTier] {
    ModelTier.allCases.filter(isInstalled)
  }

  func modelFileURL(for tier: ModelTier) -> URL {
    modelsDirectory.appendingPathComponent("ggml-\(tier.rawValue).bin")
  }

  func removeModel(_ tier: ModelTier) async throws -> Bool {
    let modelURL = modelFileURL(for: tier)
    guard fileManager.fileExists(atPath: modelURL.path) else {
      return false
    }

    try fileManager.removeItem(at: modelURL)
    try await syncInstalledModelsWithSettings()
    return true
  }

  private func syncInstalledModelsWithSettings() async throws {
    let installed = ModelTier.allCases.filter { tier in
      fileManager.fileExists(atPath: self.modelFileURL(for: tier).path)
    }
    _ = await settingsStore.update { settings in
      settings.installedModels = installed
    }
  }

  private func ensureModelDirectory() throws {
    try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
  }

  private func copyBundledModelIfAvailable(
    _ tier: ModelTier,
    descriptor: ModelDescriptor,
    to destinationURL: URL
  ) throws -> Bool {
    guard let resourceRootURL else {
      return false
    }

    let bundledModelURL = resourceRootURL
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent("ggml-\(tier.rawValue).bin")

    guard fileManager.fileExists(atPath: bundledModelURL.path) else {
      return false
    }

    if fileManager.fileExists(atPath: destinationURL.path) {
      try fileManager.removeItem(at: destinationURL)
    }

    try fileManager.copyItem(at: bundledModelURL, to: destinationURL)

    do {
      try verifyChecksum(of: destinationURL, expected: descriptor.sha256)
    } catch {
      try? fileManager.removeItem(at: destinationURL)
      throw error
    }

    return true
  }

  private func shouldValidateHash(_ value: String) -> Bool {
    let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
    return value.count == 64 && value.rangeOfCharacter(from: allowed.inverted) == nil
  }

  private func verifyChecksum(of fileURL: URL, expected expectedDigest: String) throws {
    let digest = try sha256(of: fileURL)
    if digest.lowercased() != expectedDigest.lowercased() {
      throw FridayError.transcriptionFailed("model checksum mismatch")
    }
  }

  private func fileSize(at fileURL: URL) throws -> Int64 {
    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
    return attributes[.size] as? Int64 ?? 0
  }

  private func sha256(of fileURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer {
      try? handle.close()
    }

    var hasher = SHA256()

    while true {
      let data = try handle.read(upToCount: 1_048_576) ?? Data()
      if data.isEmpty {
        break
      }
      hasher.update(data: data)
    }

    let digest = hasher.finalize()
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
