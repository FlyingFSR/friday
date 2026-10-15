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

/// Installs models as a directory of files (`models/<tier>/`), each pinned by SHA-256.
actor ModelManager {
  private let settingsStore: any SettingsStoreControlling
  private let modelsDirectory: URL
  private let fileManager: FileManager
  private let modelCatalog: [ModelTier: ModelDescriptor]
  private let downloadSession: any ModelDownloadSession
  private let resourceRootURL: URL?
  // Tiers whose files were all verified during this launch. Hashing the 2.2 GB
  // weights costs about a second, and `ensureModelInstalled` runs on every
  // transcription; the checksum guards installs, not the hot path.
  private var verifiedTiers: Set<ModelTier> = []

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

  /// Returns the model directory once every file in it matches its pinned checksum, copying
  /// from the app bundle or downloading whatever is missing or wrong.
  func ensureModelInstalled(_ tier: ModelTier) async throws -> URL {
    let descriptor = try descriptor(for: tier)
    guard !descriptor.files.isEmpty, descriptor.files.allSatisfy({ isValidHash($0.sha256) }) else {
      throw FridayError.modelChecksumUnavailable(tier.rawValue)
    }

    let directory = modelDirectoryURL(for: tier)
    if verifiedTiers.contains(tier), allFilesPresent(descriptor, in: directory) {
      return directory
    }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    for file in descriptor.files {
      let destination = directory.appendingPathComponent(file.name)
      if fileManager.fileExists(atPath: destination.path) {
        if (try? verify(destination, against: file)) != nil {
          continue
        }
        try? fileManager.removeItem(at: destination)
      }
      if try copyBundledFileIfAvailable(tier, file: file, to: destination) {
        continue
      }
      try await download(file, from: descriptor.baseURL, to: destination)
    }

    verifiedTiers.insert(tier)
    try await syncInstalledModelsWithSettings()
    return directory
  }

  func isInstalled(_ tier: ModelTier) -> Bool {
    if let descriptor = modelCatalog[tier] {
      return allFilesPresent(descriptor, in: modelDirectoryURL(for: tier))
    }
    return fileManager.fileExists(atPath: legacyWhisperFileURL(for: tier).path)
  }

  func installedModels() async -> [ModelTier] {
    ModelTier.allCases.filter(isInstalled)
  }

  func modelDirectoryURL(for tier: ModelTier) -> URL {
    modelsDirectory.appendingPathComponent(tier.rawValue, isDirectory: true)
  }

  /// Where Friday 0.4 kept a Whisper model (one ggml file).
  func legacyWhisperFileURL(for tier: ModelTier) -> URL {
    modelsDirectory.appendingPathComponent("ggml-\(tier.rawValue).bin")
  }

  /// Removes a catalog model's directory, or a Friday 0.4 Whisper file for retired tiers.
  func removeModel(_ tier: ModelTier) async throws -> Bool {
    verifiedTiers.remove(tier)
    let target = modelCatalog[tier] != nil ? modelDirectoryURL(for: tier) : legacyWhisperFileURL(for: tier)
    guard fileManager.fileExists(atPath: target.path) else {
      return false
    }

    try fileManager.removeItem(at: target)
    try await syncInstalledModelsWithSettings()
    return true
  }

  private func download(_ file: ModelFile, from baseURL: String, to destination: URL) async throws {
    guard let sourceURL = URL(string: baseURL)?.appendingPathComponent(file.name) else {
      throw FridayError.modelNotFound
    }

    let (downloadedURL, response): (URL, URLResponse)
    do {
      (downloadedURL, response) = try await downloadSession.download(from: sourceURL)
    } catch {
      throw FridayError.modelDownloadFailed("\(file.name): \(error.localizedDescription)")
    }
    defer {
      try? fileManager.removeItem(at: downloadedURL)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw FridayError.modelDownloadFailed("\(file.name): unexpected response type")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw FridayError.modelDownloadFailed("\(file.name): HTTP \(httpResponse.statusCode)")
    }

    do {
      try verify(downloadedURL, against: file)
    } catch {
      throw FridayError.modelDownloadFailed("\(file.name): checksum mismatch")
    }

    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.moveItem(at: downloadedURL, to: destination)
  }

  private func copyBundledFileIfAvailable(
    _ tier: ModelTier,
    file: ModelFile,
    to destination: URL
  ) throws -> Bool {
    guard let resourceRootURL else {
      return false
    }

    let bundled = resourceRootURL
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent(tier.rawValue, isDirectory: true)
      .appendingPathComponent(file.name)
    guard fileManager.fileExists(atPath: bundled.path) else {
      return false
    }

    try fileManager.copyItem(at: bundled, to: destination)
    do {
      try verify(destination, against: file)
    } catch {
      try? fileManager.removeItem(at: destination)
      throw error
    }
    return true
  }

  private func syncInstalledModelsWithSettings() async throws {
    let installed = ModelTier.allCases.filter(isInstalled)
    _ = await settingsStore.update { settings in
      settings.installedModels = installed
    }
  }

  private func allFilesPresent(_ descriptor: ModelDescriptor, in directory: URL) -> Bool {
    descriptor.files.allSatisfy {
      fileManager.fileExists(atPath: directory.appendingPathComponent($0.name).path)
    }
  }

  private func isValidHash(_ value: String) -> Bool {
    let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
    return value.count == 64 && value.rangeOfCharacter(from: allowed.inverted) == nil
  }

  /// Size first (cheap, catches truncated downloads), then SHA-256.
  private func verify(_ fileURL: URL, against file: ModelFile) throws {
    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
    guard size == file.sizeBytes, try sha256(of: fileURL) == file.sha256.lowercased() else {
      throw FridayError.modelDownloadFailed("\(file.name): checksum mismatch")
    }
  }

  private func sha256(of fileURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer {
      try? handle.close()
    }

    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: 4_194_304) ?? Data()
      if data.isEmpty {
        break
      }
      hasher.update(data: data)
    }

    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
