import Foundation

extension FridayController {
  private var largeModelInstallBackoffInterval: TimeInterval { 24 * 60 * 60 }
  private var minimumLargeModelFreeDiskBytes: Int64 { 4 * 1024 * 1024 * 1024 }

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
      log("Default model set to \(tier.rawValue)")
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

  func scheduleLargeModelInstallIfNeeded(reason: String) {
    if settings.installedModels.contains(.largeV3) {
      return
    }
    if largeModelInstallTask != nil {
      return
    }

    let now = Date()
    if let backoffUntil = largeModelInstallBackoffUntil, backoffUntil > now {
      log("Skipped large-v3 auto-install (backoff active until \(backoffUntil.ISO8601Format())).")
      return
    }

    guard hasEnoughDiskSpaceForLargeModel() else {
      let nextAttempt = now.addingTimeInterval(largeModelInstallBackoffInterval)
      setLargeModelInstallBackoff(until: nextAttempt)
      log("Skipped large-v3 auto-install (low disk space). Next attempt after \(nextAttempt.ISO8601Format()).")
      return
    }

    largeModelInstallTask = Task { [weak self] in
      guard let self else { return }
      self.log("Starting background large-v3 install (\(reason)).")
      defer {
        self.largeModelInstallTask = nil
      }

      do {
        _ = try await self.modelManager.ensureModelInstalled(.largeV3)
        await self.refreshInstalledModelsFromDisk()
        self.setLargeModelInstallBackoff(until: nil)
        self.log("Background large-v3 install completed.")
      } catch {
        let nextAttempt = Date().addingTimeInterval(self.largeModelInstallBackoffInterval)
        self.setLargeModelInstallBackoff(until: nextAttempt)
        self.log(
          "Background large-v3 install failed: \(error.localizedDescription). " +
          "Next attempt after \(nextAttempt.ISO8601Format())."
        )
      }
    }
  }

  func hasEnoughDiskSpaceForLargeModel() -> Bool {
    do {
      let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
      let freeBytes = attributes[.systemFreeSize] as? Int64 ?? 0
      return freeBytes >= minimumLargeModelFreeDiskBytes
    } catch {
      return false
    }
  }

  func setLargeModelInstallBackoff(until date: Date?) {
    largeModelInstallBackoffUntil = date
    if let date {
      UserDefaults.standard.set(date.timeIntervalSince1970, forKey: FridayController.largeModelInstallBackoffKey)
    } else {
      UserDefaults.standard.removeObject(forKey: FridayController.largeModelInstallBackoffKey)
    }
  }

  func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(stamp)] \(message)"
    diagnostics.insert(line, at: 0)
    appendDiagnosticsToDisk(line)
    if diagnostics.count > 120 {
      diagnostics = Array(diagnostics.prefix(120))
    }
  }

  func transcriptScriptStats(_ text: String) -> String {
    let scalars = text.unicodeScalars
    let cjkCount = scalars.filter { scalar in
      (0x4E00...0x9FFF).contains(scalar.value) ||
      (0x3400...0x4DBF).contains(scalar.value)
    }.count
    let latinCount = scalars.filter { scalar in
      CharacterSet.letters.contains(scalar) && scalar.value < 0x024F
    }.count
    return "len=\(text.count), cjk=\(cjkCount), latin=\(latinCount)"
  }
}
