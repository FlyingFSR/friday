import AppKit
import Foundation

extension FridayController {
  func bootstrap() {
    guard !hasBootstrapped else {
      return
    }
    hasBootstrapped = true

    // Keep this synchronous and before Task to ensure menu bar icon appears immediately.
    statusBarController = StatusBarController(controller: self)

    if didBecomeActiveObserver == nil {
      didBecomeActiveObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.refreshPermissions()
          self?.startHotkeyIfPossible()
          self?.startPermissionPolling(duration: 5)
          self?.updateOnboardingRequirement()
          self?.statusBarController?.ensureVisible()
        }
      }
    }

    Task {
      settings = await settingsStore.load()
      await migrateAwayFromLargeV3IfNeeded()
      cleanupStaleArtifactsOnBootstrap()
      refreshPermissions()
      startPermissionPolling(duration: 6)
      await refreshInstalledModelsFromDisk()
      await startWhisperServerIfModelReady()
      onboardingWindowController = OnboardingWindowController(controller: self)
      startHotkeyIfPossible()
      updateOnboardingRequirement()
      statusBarController?.ensureVisible()
      log("Friday initialized")
    }
  }

  func openSetupAssistant() {
    if onboardingWindowController == nil {
      onboardingWindowController = OnboardingWindowController(controller: self)
    }
    onboardingWindowController?.show()
  }

  func handleExternalActivationRequest() {
    NSApp.activate(ignoringOtherApps: true)
    statusBarController?.ensureVisible()
    openSetupAssistant()
    log("Activation request received from a second launch")
  }

  func shutdown() {
    whisperServer.stop()
    permissionPollingTask?.cancel()
    permissionPollingTask = nil
    pendingIdleResetTask?.cancel()
    pendingIdleResetTask = nil
    transcriptionTask?.cancel()
    transcriptionTask = nil

    if let didBecomeActiveObserver {
      NotificationCenter.default.removeObserver(didBecomeActiveObserver)
      self.didBecomeActiveObserver = nil
    }
    hotkeyService.stop()
    audioCaptureService.stopContinuousCapture()
  }

  func updateOnboardingRequirement() {
    let hasDefaultModel = settings.installedModels.contains(settings.defaultModel)
    requiresOnboarding = !(permissions.allGranted && hasDefaultModel)
    if requiresOnboarding, !didAutoPresentOnboardingThisSession {
      didAutoPresentOnboardingThisSession = true
      onboardingWindowController?.show()
    } else if !requiresOnboarding {
      didAutoPresentOnboardingThisSession = false
    }
  }

  func startPermissionPolling(duration: TimeInterval) {
    permissionPollingTask?.cancel()
    permissionPollingTask = Task { [weak self] in
      guard let self else { return }

      let intervalNanos: UInt64 = 500_000_000
      let ticks = max(1, Int((duration / 0.5).rounded()))

      for _ in 0..<ticks {
        if Task.isCancelled { return }

        self.refreshPermissions()
        self.startHotkeyIfPossible()
        self.updateOnboardingRequirement()

        if self.permissions.allGranted {
          return
        }

        try? await Task.sleep(nanoseconds: intervalNanos)
      }
    }
  }

  /// Friday no longer ships Large v3 (replaced by the faster Turbo model).
  /// Migrate any saved default still pointing at large-v3 over to Turbo
  /// (or Medium if Turbo isn't installed yet) and delete the obsolete ~3 GB
  /// weight file so upgrading users reclaim the disk space.
  func migrateAwayFromLargeV3IfNeeded() async {
    if settings.defaultModel == .largeV3 {
      let replacement: ModelTier = settings.installedModels.contains(.turbo) ? .turbo : .medium
      settings = await settingsStore.update { settings in
        settings.defaultModel = replacement
      }
      log("Migrated default model large-v3 -> \(replacement.rawValue)")
    }

    if (try? await modelManager.removeModel(.largeV3)) == true {
      log("Removed obsolete large-v3 weight file from disk")
    }
  }

  func refreshInstalledModelsFromDisk() async {
    let installed = await modelManager.installedModels().filter { $0 == .medium || $0 == .turbo }
    let updated = await settingsStore.update { settings in
      settings.installedModels = installed
      settings.defaultModel = Self.preferredTranscriptionModel(
        defaultModel: settings.defaultModel,
        installedModels: installed
      ) ?? .medium
    }
    settings = updated
  }

  func startWhisperServerIfModelReady() async {
    guard let modelTier = Self.preferredTranscriptionModel(
      defaultModel: settings.defaultModel,
      installedModels: settings.installedModels
    ) else {
      log("whisper-server not started: no installed transcription model")
      return
    }

    do {
      let modelURL = try await modelManager.ensureModelInstalled(modelTier)
      try await whisperServer.start(modelPath: modelURL.path, vadModelPath: nil)
      log("whisper-server started with model \(modelTier.rawValue) vad=off")
    } catch {
      log("whisper-server failed to start: \(error.localizedDescription)")
    }
  }

  static func preferredTranscriptionModel(
    defaultModel: ModelTier,
    installedModels: [ModelTier]
  ) -> ModelTier? {
    if installedModels.contains(defaultModel), defaultModel == .medium || defaultModel == .turbo {
      return defaultModel
    }
    if installedModels.contains(.medium) {
      return .medium
    }
    if installedModels.contains(.turbo) {
      return .turbo
    }
    return nil
  }

  func cleanupStaleArtifactsOnBootstrap() {
    guard settings.retention.lowercased() == "none" else {
      return
    }

    let tempDirectory = fileManager.temporaryDirectory
    let recordingDirectory = tempDirectory.appendingPathComponent("friday-recordings", isDirectory: true)
    if fileManager.fileExists(atPath: recordingDirectory.path) {
      try? fileManager.removeItem(at: recordingDirectory)
    }

    guard let entries = try? fileManager.contentsOfDirectory(
      at: tempDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsSubdirectoryDescendants]
    ) else {
      return
    }

    for entry in entries where entry.lastPathComponent.hasPrefix("friday-transcript-") {
      try? fileManager.removeItem(at: entry)
    }
  }
}
