import Foundation

extension FridayController {
  func prepareDiagnosticsLogFileIfNeeded() {
    let directory = diagnosticsLogURL.deletingLastPathComponent()
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    if !fileManager.fileExists(atPath: diagnosticsLogURL.path) {
      fileManager.createFile(atPath: diagnosticsLogURL.path, contents: Data())
    }
  }

  func appendDiagnosticsToDisk(_ line: String) {
    rotateDiagnosticsLogIfNeeded()
    guard let handle = try? FileHandle(forWritingTo: diagnosticsLogURL) else {
      return
    }
    defer {
      try? handle.close()
    }

    do {
      try handle.seekToEnd()
      if let payload = (line + "\n").data(using: .utf8) {
        try handle.write(contentsOf: payload)
      }
    } catch {
      // Swallow logging I/O errors to avoid impacting runtime flow.
    }
  }

  func rotateDiagnosticsLogIfNeeded() {
    let maxBytes: Int64 = 512 * 1024
    guard let attributes = try? fileManager.attributesOfItem(atPath: diagnosticsLogURL.path),
          let fileSize = attributes[.size] as? Int64,
          fileSize > maxBytes else {
      return
    }

    try? fileManager.removeItem(at: diagnosticsLogURL)
    fileManager.createFile(atPath: diagnosticsLogURL.path, contents: Data())
  }

  func setDefaultModel(_ tier: ModelTier) {
    guard settings.installedModels.contains(tier) else {
      statusMessage = "\(tier.displayName) is not installed."
      log("Ignored default model change: \(tier.rawValue) is not installed")
      return
    }

    Task {
      let updated = await settingsStore.update { settings in
        settings.defaultModel = tier
      }
      settings = updated
      statusMessage = "Switching to \(tier.displayName)…"
      log("Default model set to \(tier.rawValue), restarting whisper-server")
      await startWhisperServerIfModelReady()
      updateOnboardingRequirement()
    }
  }

  func installModel(_ tier: ModelTier) {
    Task {
      downloadingModel = tier
      statusMessage = "Downloading \(tier.displayName)..."
      hudController.show(state: .transcribing, message: statusMessage, duration: nil, showsCompletionCheck: false)
      do {
        _ = try await modelManager.ensureModelInstalled(tier)
        await refreshInstalledModelsFromDisk()
        await startWhisperServerIfModelReady()
        statusMessage = "\(tier.displayName) model ready"
        pipelineState = .pasted
        hudController.show(state: .pasted, message: statusMessage, duration: nil, showsCompletionCheck: true)
      } catch {
        fail(error.localizedDescription, sessionID: activeSessionID)
      }
      downloadingModel = nil
      updateOnboardingRequirement()
      scheduleIdleReset(seconds: 1.0, sessionID: activeSessionID)
    }
  }

  func descriptor(for tier: ModelTier) -> ModelDescriptor? {
    ModelCatalog.all[tier]
  }

  private static let diagnosticsTimestampFormatter = ISO8601DateFormatter()

  func log(_ message: String) {
    let stamp = Self.diagnosticsTimestampFormatter.string(from: Date())
    let line = "[\(stamp)] \(message)"
    diagnostics.insert(line, at: 0)
    appendDiagnosticsToDisk(line)
    if diagnostics.count > 120 {
      diagnostics = Array(diagnostics.prefix(120))
    }
  }

  func transcriptScriptStats(_ text: String) -> String {
    let counts = LanguageDetector.scriptCounts(in: text)
    return "len=\(text.count), cjk=\(counts.cjk), latin=\(counts.latin)"
  }
}
