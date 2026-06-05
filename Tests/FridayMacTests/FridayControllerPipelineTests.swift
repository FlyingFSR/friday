import Foundation
import Testing
@testable import FridayMac

@MainActor
struct FridayControllerPipelineTests {
  @Test
  func oldIdleResetDoesNotOverrideNewRecordingSession() async throws {
    let settingsStore = MockSettingsStore()
    let permissionService = MockPermissionService(allGranted: true)
    let hotkeyService = MockHotkeyService()
    let audioCaptureService = MockAudioCaptureService()
    let pasteService = MockPasteService()
    let transcriptionService = MockTranscriptionService()
    transcriptionService.handler = { _ in
      TranscriptionResult(
        text: "hello world",
        detectedLanguage: .en,
        durationMs: 120,
        artifactPaths: []
      )
    }

    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: permissionService,
      hotkeyService: hotkeyService,
      audioCaptureService: audioCaptureService,
      pasteService: pasteService,
      transcriptionService: transcriptionService
    )

    hotkeyService.triggerPress()
    hotkeyService.triggerRelease()

    for _ in 0..<20 {
      if controller.pipelineState == .pasted {
        break
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    #expect(controller.pipelineState == .pasted)

    hotkeyService.triggerPress()
    for _ in 0..<20 {
      if controller.pipelineState == .recording {
        break
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(controller.pipelineState == .recording)

    try await Task.sleep(nanoseconds: 1_000_000_000)
    #expect(controller.pipelineState == .recording)
  }

  @Test
  func transcriptionFailureStillCleansWavAndTxtArtifacts() async throws {
    let settingsStore = MockSettingsStore()
    let permissionService = MockPermissionService(allGranted: true)
    let hotkeyService = MockHotkeyService()
    let audioCaptureService = MockAudioCaptureService()
    let pasteService = MockPasteService()
    let transcriptionService = MockTranscriptionService()
    let fileManager = FileManager.default

    let tempDirectory = fileManager.temporaryDirectory
    let wavPath = tempDirectory.appendingPathComponent("friday-test-\(UUID().uuidString).wav").path
    let txtPath = tempDirectory.appendingPathComponent("friday-test-\(UUID().uuidString).txt").path
    _ = fileManager.createFile(atPath: wavPath, contents: Data("wav".utf8))

    audioCaptureService.nextRecording = RecordingResult(
      fileURL: URL(fileURLWithPath: wavPath),
      duration: 0.8
    )
    transcriptionService.handler = { _ in
      _ = fileManager.createFile(atPath: txtPath, contents: Data("artifact".utf8))
      throw TranscriptionFailure(reason: "forced failure", artifactPaths: [txtPath])
    }

    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: permissionService,
      hotkeyService: hotkeyService,
      audioCaptureService: audioCaptureService,
      pasteService: pasteService,
      transcriptionService: transcriptionService
    )
    #expect(controller.pipelineState == .idle)

    hotkeyService.triggerPress()
    hotkeyService.triggerRelease()
    try await Task.sleep(nanoseconds: 350_000_000)

    #expect(!fileManager.fileExists(atPath: wavPath))
    #expect(!fileManager.fileExists(atPath: txtPath))
  }

  @Test
  func deadServerIsRestartedOnceAndTranscriptionRetried() async throws {
    let settingsStore = MockSettingsStore()
    let permissionService = MockPermissionService(allGranted: true)
    let hotkeyService = MockHotkeyService()
    let audioCaptureService = MockAudioCaptureService()
    let pasteService = MockPasteService()
    let transcriptionService = MockTranscriptionService()
    let whisperServer = MockWhisperServerManager()

    transcriptionService.handler = { _ in
      // First attempt: server is dead → connection refused. After restart the
      // retry succeeds.
      if transcriptionService.callCount == 1 {
        throw URLError(.cannotConnectToHost)
      }
      return TranscriptionResult(
        text: "recovered text",
        detectedLanguage: .en,
        durationMs: 10,
        artifactPaths: []
      )
    }

    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: permissionService,
      hotkeyService: hotkeyService,
      audioCaptureService: audioCaptureService,
      pasteService: pasteService,
      transcriptionService: transcriptionService,
      whisperServer: whisperServer
    )

    hotkeyService.triggerPress()
    hotkeyService.triggerRelease()

    for _ in 0..<40 {
      if controller.pipelineState == .pasted {
        break
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(controller.pipelineState == .pasted)
    #expect(whisperServer.restartAttempts == 1)
    #expect(transcriptionService.callCount == 2)
    #expect(pasteService.pastedText == "recovered text")
  }

  @Test
  func transcriptionTimeoutDoesNotRestartServer() async throws {
    let settingsStore = MockSettingsStore()
    let permissionService = MockPermissionService(allGranted: true)
    let hotkeyService = MockHotkeyService()
    let audioCaptureService = MockAudioCaptureService()
    let pasteService = MockPasteService()
    let transcriptionService = MockTranscriptionService()
    let whisperServer = MockWhisperServerManager()

    // A timeout means the server is alive but slow; restarting it would kill a
    // working process, so the pipeline must not recover here.
    transcriptionService.handler = { _ in
      throw URLError(.timedOut)
    }

    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: permissionService,
      hotkeyService: hotkeyService,
      audioCaptureService: audioCaptureService,
      pasteService: pasteService,
      transcriptionService: transcriptionService,
      whisperServer: whisperServer
    )

    hotkeyService.triggerPress()
    hotkeyService.triggerRelease()

    for _ in 0..<40 {
      if controller.pipelineState == .error {
        break
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(controller.pipelineState == .error)
    #expect(whisperServer.restartAttempts == 0)
    #expect(transcriptionService.callCount == 1)
  }

  @Test
  func failedServerRestartSurfacesErrorWithoutRetry() async throws {
    let settingsStore = MockSettingsStore()
    let permissionService = MockPermissionService(allGranted: true)
    let hotkeyService = MockHotkeyService()
    let audioCaptureService = MockAudioCaptureService()
    let pasteService = MockPasteService()
    let transcriptionService = MockTranscriptionService()
    let whisperServer = MockWhisperServerManager()
    whisperServer.restartError = FridayError.whisperServerStartFailed

    transcriptionService.handler = { _ in
      throw URLError(.cannotConnectToHost)
    }

    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: permissionService,
      hotkeyService: hotkeyService,
      audioCaptureService: audioCaptureService,
      pasteService: pasteService,
      transcriptionService: transcriptionService,
      whisperServer: whisperServer
    )

    hotkeyService.triggerPress()
    hotkeyService.triggerRelease()

    for _ in 0..<40 {
      if controller.pipelineState == .error {
        break
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(controller.pipelineState == .error)
    #expect(whisperServer.restartAttempts == 1)
    // Restart failed, so the transcription is not retried.
    #expect(transcriptionService.callCount == 1)
  }

  @Test
  func whisperServerStartupDoesNotEnableVADByDefault() async throws {
    let settingsStore = MockSettingsStore()
    let permissionService = MockPermissionService(allGranted: true)
    let hotkeyService = MockHotkeyService()
    let audioCaptureService = MockAudioCaptureService()
    let pasteService = MockPasteService()
    let transcriptionService = MockTranscriptionService()
    let modelManager = MockModelManager()
    let whisperServer = MockWhisperServerManager()

    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: permissionService,
      hotkeyService: hotkeyService,
      audioCaptureService: audioCaptureService,
      pasteService: pasteService,
      transcriptionService: transcriptionService,
      modelManager: modelManager,
      whisperServer: whisperServer
    )

    await controller.startWhisperServerIfModelReady()

    #expect(modelManager.vadInstallAttempts == 0)
    #expect(whisperServer.lastVADModelPath == nil)
  }

  @Test
  func whisperServerStartupSkipsWhenDefaultModelIsMissing() async throws {
    let settingsStore = MockSettingsStore()
    settingsStore.current.installedModels = []
    let permissionService = MockPermissionService(allGranted: true)
    let hotkeyService = MockHotkeyService()
    let audioCaptureService = MockAudioCaptureService()
    let pasteService = MockPasteService()
    let transcriptionService = MockTranscriptionService()
    let modelManager = MockModelManager()
    modelManager.installed = []
    let whisperServer = MockWhisperServerManager()

    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: permissionService,
      hotkeyService: hotkeyService,
      audioCaptureService: audioCaptureService,
      pasteService: pasteService,
      transcriptionService: transcriptionService,
      modelManager: modelManager,
      whisperServer: whisperServer
    )
    controller.settings = settingsStore.current

    await controller.startWhisperServerIfModelReady()

    #expect(modelManager.ensureAttempts == 0)
    #expect(whisperServer.startAttempts == 0)
  }

  @Test
  func installModelStartsWhisperServerAfterModelBecomesReady() async throws {
    let settingsStore = MockSettingsStore()
    settingsStore.current.installedModels = []
    let permissionService = MockPermissionService(allGranted: true)
    let hotkeyService = MockHotkeyService()
    let audioCaptureService = MockAudioCaptureService()
    let pasteService = MockPasteService()
    let transcriptionService = MockTranscriptionService()
    let modelManager = MockModelManager()
    modelManager.installed = []
    let whisperServer = MockWhisperServerManager()

    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: permissionService,
      hotkeyService: hotkeyService,
      audioCaptureService: audioCaptureService,
      pasteService: pasteService,
      transcriptionService: transcriptionService,
      modelManager: modelManager,
      whisperServer: whisperServer
    )
    controller.settings = settingsStore.current

    controller.installModel(.medium)
    try await Task.sleep(nanoseconds: 250_000_000)

    #expect(modelManager.ensureAttempts == 2)
    #expect(whisperServer.startAttempts == 1)
    #expect(whisperServer.lastModelPath == "/tmp/mock-model.bin")
  }

  private func makeController(
    settingsStore: MockSettingsStore,
    permissionService: MockPermissionService,
    hotkeyService: MockHotkeyService,
    audioCaptureService: MockAudioCaptureService,
    pasteService: MockPasteService,
    transcriptionService: MockTranscriptionService,
    modelManager: MockModelManager = MockModelManager(),
    whisperServer: MockWhisperServerManager = MockWhisperServerManager()
  ) -> FridayController {
    FridayController(
      dependencies: FridayDependencies(
        settingsStore: settingsStore,
        permissionService: permissionService,
        hotkeyService: hotkeyService,
        audioCaptureService: audioCaptureService,
        postProcessService: MockPostProcessService(),
        focusSafetyService: MockFocusSafetyService(),
        pasteService: pasteService,
        autoLaunchService: MockAutoLaunchService(),
        hudController: MockHUDController(),
        modelManager: modelManager,
        transcriptionService: transcriptionService,
        whisperServer: whisperServer,
        fileManager: .default
      )
    )
  }
}

private final class MockSettingsStore: SettingsStoreControlling {
  var current = FridaySettings.default

  func load() async -> FridaySettings {
    current
  }

  func update(_ mutate: (inout FridaySettings) -> Void) async -> FridaySettings {
    mutate(&current)
    return current
  }
}

private final class MockPermissionService: PermissionServicing {
  let allGranted: Bool

  init(allGranted: Bool) {
    self.allGranted = allGranted
  }

  func snapshot() -> PermissionSnapshot {
    PermissionSnapshot(microphone: allGranted, accessibility: allGranted, inputMonitoring: allGranted)
  }

  func microphoneGranted() -> Bool { allGranted }
  func requestMicrophone() async -> Bool { allGranted }
  func accessibilityGranted() -> Bool { allGranted }
  func requestAccessibilityPrompt() -> Bool { allGranted }
  func inputMonitoringGranted() -> Bool { allGranted }
  func requestInputMonitoringPrompt() -> Bool { allGranted }
  func openMicrophoneSettings() {}
  func openAccessibilitySettings() {}
  func openInputMonitoringSettings() {}
}

private final class MockHotkeyService: HotkeyServicing {
  var onPress: (() -> Void)?
  var onRelease: (() -> Void)?
  var isRunning: Bool = true

  func start() throws {
    isRunning = true
  }

  func stop() {
    isRunning = false
  }

  func triggerPress() {
    onPress?()
  }

  func triggerRelease() {
    onRelease?()
  }
}

private final class MockAudioCaptureService: AudioCaptureServicing {
  var isContinuousCaptureRunning = false
  var onLevelUpdate: ((Float) -> Void)?
  var nextRecording = RecordingResult(
    fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).wav"),
    duration: 0.6
  )
  private var sessionActive = false

  func startContinuousCapture() throws {
    isContinuousCaptureRunning = true
  }

  func stopContinuousCapture() {
    isContinuousCaptureRunning = false
    sessionActive = false
  }

  func beginSession() throws {
    guard isContinuousCaptureRunning else {
      throw FridayError.recordingNotActive
    }
    guard !sessionActive else {
      throw FridayError.recordingAlreadyActive
    }
    sessionActive = true
  }

  func endSession() throws -> RecordingResult {
    guard sessionActive else {
      throw FridayError.recordingNotActive
    }
    sessionActive = false
    return nextRecording
  }
}

private final class MockPostProcessService: PostProcessServicing {
  func cleanup(_ rawText: String, mode: TextCleanupMode) -> String {
    rawText
  }
}

private final class MockFocusSafetyService: FocusSafetyServicing {
  func shouldBlockPaste(blockSecureInput: Bool) -> Bool {
    false
  }
}

private final class MockPasteService: PasteServicing {
  var pastedText: String?
  var copiedText: String?

  func paste(_ text: String, restoreClipboard: Bool) throws {
    pastedText = text
  }

  func copyToClipboard(_ text: String) throws {
    copiedText = text
  }
}

private final class MockAutoLaunchService: AutoLaunchServicing {
  func setEnabled(_ enabled: Bool) throws {}
}

private final class MockModelManager: ModelManaging {
  var vadInstallAttempts = 0
  var ensureAttempts = 0
  var installed: [ModelTier] = [.medium]

  func ensureModelInstalled(_ tier: ModelTier) async throws -> URL {
    ensureAttempts += 1
    if !installed.contains(tier) {
      installed.append(tier)
    }
    return URL(fileURLWithPath: "/tmp/mock-model.bin")
  }

  func ensureVADModelInstalled() async throws -> URL {
    vadInstallAttempts += 1
    return URL(fileURLWithPath: "/tmp/mock-vad-model.bin")
  }

  func installedModels() async -> [ModelTier] {
    installed
  }

  func removeModel(_ tier: ModelTier) async throws -> Bool {
    false
  }
}

private final class MockTranscriptionService: TranscriptionServicing {
  var handler: ((TranscriptionRequest) async throws -> TranscriptionResult)?
  private(set) var callCount = 0

  func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult {
    callCount += 1
    guard let handler else {
      throw FridayError.transcriptionFailed("missing mock handler")
    }
    return try await handler(request)
  }
}

private final class MockWhisperServerManager: WhisperServerManaging {
  var isReady = true
  var baseURL: URL { URL(string: "http://127.0.0.1:8178")! }
  var lastVADModelPath: String?
  var lastModelPath: String?
  var startAttempts = 0
  var restartAttempts = 0
  var restartError: Error?

  func start(modelPath: String, vadModelPath: String?) async throws {
    startAttempts += 1
    lastModelPath = modelPath
    lastVADModelPath = vadModelPath
  }

  func restart() async throws {
    restartAttempts += 1
    if let restartError {
      throw restartError
    }
  }

  func stop() {}
}

@MainActor
private final class MockHUDController: HUDControlling {
  func show(
    state: PipelineState,
    message: String,
    duration: TimeInterval?,
    showsCompletionCheck: Bool
  ) {}

  func update(level: Float) {}

  func hide() {}
}
