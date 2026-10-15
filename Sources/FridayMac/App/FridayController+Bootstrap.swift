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
      hotkeyService.setSelectedHotkey(settings.pushToTalkKey)
      await migrateAwayFromRetiredModelsIfNeeded()
      cleanupStaleArtifactsOnBootstrap()
      logRuntimeVersions()
      refreshPermissions()
      startPermissionPolling(duration: 6)
      await refreshInstalledModelsFromDisk()
      await loadSpeechEngineIfModelReady()
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

  /// Friday 0.5 transcribes with Qwen3-ASR. Saved defaults that still name a Whisper model
  /// (Medium, or the earlier Base/Small/Large v3/Turbo) move over to Qwen3-ASR. The retired
  /// Large v3 and Turbo weight files are deleted as before; the Medium file is deliberately kept
  /// so going back to Friday 0.4 does not require a 1.5 GB download.
  func migrateAwayFromRetiredModelsIfNeeded() async {
    let retiredModels: [ModelTier] = [.largeV3, .turbo]

    if settings.defaultModel != .qwen3ASR {
      let previous = settings.defaultModel
      settings = await settingsStore.update { settings in
        settings.defaultModel = .qwen3ASR
      }
      log("Migrated default model \(previous.rawValue) -> \(ModelTier.qwen3ASR.rawValue)")
    }

    for tier in retiredModels {
      if (try? await modelManager.removeModel(tier)) == true {
        log("Removed obsolete \(tier.rawValue) weight file from disk")
      }
    }
  }

  func refreshInstalledModelsFromDisk() async {
    let installed = await modelManager.installedModels().filter { $0 == .qwen3ASR }
    let updated = await settingsStore.update { settings in
      settings.installedModels = installed
      settings.defaultModel = Self.preferredTranscriptionModel(
        defaultModel: settings.defaultModel,
        installedModels: installed
      ) ?? .qwen3ASR
    }
    settings = updated
  }

  /// Loads the speech engine in the background so the first dictation is fast. Transcription
  /// also loads it on demand, so a failure here only costs latency on that first dictation.
  func loadSpeechEngineIfModelReady() async {
    guard let modelTier = Self.preferredTranscriptionModel(
      defaultModel: settings.defaultModel,
      installedModels: settings.installedModels
    ) else {
      log("Speech engine not loaded: no installed transcription model")
      return
    }

    do {
      let startedAt = Date()
      let modelDirectory = try await modelManager.ensureModelInstalled(modelTier)
      try await speechEngine.load(modelDirectory: modelDirectory)
      let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
      log("Speech engine loaded with model \(modelTier.rawValue) in \(ms) ms")
    } catch {
      log("Speech engine failed to load: \(error.localizedDescription)")
    }
  }

  static func preferredTranscriptionModel(
    defaultModel: ModelTier,
    installedModels: [ModelTier]
  ) -> ModelTier? {
    installedModels.contains(.qwen3ASR) ? .qwen3ASR : nil
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
