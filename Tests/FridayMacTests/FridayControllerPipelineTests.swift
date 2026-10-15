import Foundation
import Qwen3ASR
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
  func engineErrorSurfacesWithoutRetry() async throws {
    let settingsStore = MockSettingsStore()
    let permissionService = MockPermissionService(allGranted: true)
    let hotkeyService = MockHotkeyService()
    let audioCaptureService = MockAudioCaptureService()
    let pasteService = MockPasteService()
    let transcriptionService = MockTranscriptionService()

    // The engine runs in-process: there is no server to restart, so a failure is
    // reported once instead of being retried.
    transcriptionService.handler = { _ in
      throw FridayError.speechEngineNotReady
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

    for _ in 0..<40 {
      if controller.pipelineState == .error {
        break
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(controller.pipelineState == .error)
    #expect(transcriptionService.callCount == 1)
    #expect(pasteService.pastedText == nil)
  }

  @Test
  func speechEngineLoadSkipsWhenModelIsMissing() async throws {
    let settingsStore = MockSettingsStore()
    settingsStore.current.installedModels = []
    let modelManager = MockModelManager()
    modelManager.installed = []
    let speechEngine = MockSpeechEngine()

    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: MockPermissionService(allGranted: true),
      hotkeyService: MockHotkeyService(),
      audioCaptureService: MockAudioCaptureService(),
      pasteService: MockPasteService(),
      transcriptionService: MockTranscriptionService(),
      modelManager: modelManager,
      speechEngine: speechEngine
    )
    controller.settings = settingsStore.current

    await controller.loadSpeechEngineIfModelReady()

    #expect(modelManager.ensureAttempts == 0)
    #expect(speechEngine.loadedDirectories.isEmpty)
  }

  @Test
  func installModelLoadsSpeechEngineAfterModelBecomesReady() async throws {
    let settingsStore = MockSettingsStore()
    settingsStore.current.installedModels = []
    let modelManager = MockModelManager()
    modelManager.installed = []
    let speechEngine = MockSpeechEngine()

    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: MockPermissionService(allGranted: true),
      hotkeyService: MockHotkeyService(),
      audioCaptureService: MockAudioCaptureService(),
      pasteService: MockPasteService(),
      transcriptionService: MockTranscriptionService(),
      modelManager: modelManager,
      speechEngine: speechEngine
    )
    controller.settings = settingsStore.current

    controller.installModel(.qwen3ASR)
    for _ in 0..<40 {
      if !speechEngine.loadedDirectories.isEmpty {
        break
      }
      try await Task.sleep(nanoseconds: 25_000_000)
    }

    #expect(modelManager.ensureAttempts == 2)
    #expect(speechEngine.loadedDirectories == [URL(fileURLWithPath: "/tmp/mock-model")])
  }

  @Test
  func changingPushToTalkKeyPersistsAndReconfiguresListener() async throws {
    let settingsStore = MockSettingsStore()
    let hotkeyService = MockHotkeyService()
    let controller = makeController(
      settingsStore: settingsStore,
      permissionService: MockPermissionService(allGranted: true),
      hotkeyService: hotkeyService,
      audioCaptureService: MockAudioCaptureService(),
      pasteService: MockPasteService(),
      transcriptionService: MockTranscriptionService()
    )

    controller.setPushToTalkKey(.rightOption)
    for _ in 0..<20 {
      if settingsStore.current.pushToTalkKey == .rightOption,
         hotkeyService.selectedHotkey == .rightOption {
        break
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(controller.settings.pushToTalkKey == .rightOption)
    #expect(settingsStore.current.pushToTalkKey == .rightOption)
    #expect(hotkeyService.selectedHotkey == .rightOption)
  }

  private func makeController(
    settingsStore: MockSettingsStore,
    permissionService: MockPermissionService,
    hotkeyService: MockHotkeyService,
    audioCaptureService: MockAudioCaptureService,
    pasteService: MockPasteService,
    transcriptionService: MockTranscriptionService,
    modelManager: MockModelManager = MockModelManager(),
    speechEngine: MockSpeechEngine = MockSpeechEngine()
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
        speechEngine: speechEngine,
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
  var selectedHotkey: PushToTalkKey = .rightCommand

  func setSelectedHotkey(_ hotkey: PushToTalkKey) {
    selectedHotkey = hotkey
  }

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
  var ensureAttempts = 0
  var installed: [ModelTier] = [.qwen3ASR]

  func ensureModelInstalled(_ tier: ModelTier) async throws -> URL {
    ensureAttempts += 1
    if !installed.contains(tier) {
      installed.append(tier)
    }
    return URL(fileURLWithPath: "/tmp/mock-model")
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

private final class MockSpeechEngine: SpeechEngineControlling, @unchecked Sendable {
  private(set) var loadedDirectories: [URL] = []

  var isLoaded: Bool {
    get async { !loadedDirectories.isEmpty }
  }

  func load(modelDirectory: URL) async throws {
    loadedDirectories.append(modelDirectory)
  }

  func transcribe(samples: [Float], language: String, context: String) async throws -> TranscriptionOutput {
    TranscriptionOutput(text: "", language: language, finishReasons: ["eos"])
  }
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
