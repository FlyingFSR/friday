import Foundation
import Testing
@testable import FridayMac

@MainActor
struct AutoStartConsistencyTests {
  @Test
  func autoStartSettingDoesNotDriftWhenRegistrationFails() async throws {
    let settingsStore = AutoStartSettingsStore(initialAutoStart: true)
    let autoLaunch = AutoStartMockAutoLaunchService()
    autoLaunch.error = FridayError.modelDownloadFailed("forced failure")

    let controller = makeController(settingsStore: settingsStore, autoLaunchService: autoLaunch)
    controller.settings = settingsStore.current

    controller.setAutoStart(false)
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(autoLaunch.callCount == 1)
    #expect(settingsStore.current.autoStart == true)
    #expect(controller.settings.autoStart == true)
  }

  @Test
  func autoStartSettingUpdatesAfterSuccessfulRegistration() async throws {
    let settingsStore = AutoStartSettingsStore(initialAutoStart: true)
    let autoLaunch = AutoStartMockAutoLaunchService()

    let controller = makeController(settingsStore: settingsStore, autoLaunchService: autoLaunch)
    controller.settings = settingsStore.current

    controller.setAutoStart(false)
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(autoLaunch.callCount == 1)
    #expect(settingsStore.current.autoStart == false)
    #expect(controller.settings.autoStart == false)
  }

  private func makeController(
    settingsStore: AutoStartSettingsStore,
    autoLaunchService: AutoStartMockAutoLaunchService
  ) -> FridayController {
    FridayController(
      dependencies: FridayDependencies(
        settingsStore: settingsStore,
        permissionService: AutoStartMockPermissionService(),
        hotkeyService: AutoStartMockHotkeyService(),
        audioCaptureService: AutoStartMockAudioCaptureService(),
        postProcessService: AutoStartMockPostProcessService(),
        focusSafetyService: AutoStartMockFocusSafetyService(),
        pasteService: AutoStartMockPasteService(),
        autoLaunchService: autoLaunchService,
        hudController: AutoStartMockHUDController(),
        modelManager: AutoStartMockModelManager(),
        transcriptionService: AutoStartMockTranscriptionService(),
        whisperServer: AutoStartMockWhisperServerManager(),
        fileManager: .default
      )
    )
  }
}

private final class AutoStartSettingsStore: SettingsStoreControlling {
  var current: FridaySettings

  init(initialAutoStart: Bool) {
    current = FridaySettings.default
    current.autoStart = initialAutoStart
  }

  func load() async -> FridaySettings {
    current
  }

  func update(_ mutate: (inout FridaySettings) -> Void) async -> FridaySettings {
    mutate(&current)
    return current
  }
}

private final class AutoStartMockAutoLaunchService: AutoLaunchServicing {
  var callCount = 0
  var error: Error?

  func setEnabled(_ enabled: Bool) throws {
    callCount += 1
    if let error {
      throw error
    }
  }
}

private final class AutoStartMockPermissionService: PermissionServicing {
  func snapshot() -> PermissionSnapshot {
    PermissionSnapshot(microphone: true, accessibility: true, inputMonitoring: true)
  }

  func microphoneGranted() -> Bool { true }
  func requestMicrophone() async -> Bool { true }
  func accessibilityGranted() -> Bool { true }
  func requestAccessibilityPrompt() -> Bool { true }
  func inputMonitoringGranted() -> Bool { true }
  func requestInputMonitoringPrompt() -> Bool { true }
  func openMicrophoneSettings() {}
  func openAccessibilitySettings() {}
  func openInputMonitoringSettings() {}
}

private final class AutoStartMockHotkeyService: HotkeyServicing {
  var onPress: (() -> Void)?
  var onRelease: (() -> Void)?
  var isRunning = false

  func start() throws {
    isRunning = true
  }

  func stop() {
    isRunning = false
  }
}

private final class AutoStartMockAudioCaptureService: AudioCaptureServicing {
  var isContinuousCaptureRunning = false
  var onLevelUpdate: ((Float) -> Void)?

  func startContinuousCapture() throws {
    isContinuousCaptureRunning = true
  }

  func stopContinuousCapture() {
    isContinuousCaptureRunning = false
  }

  func beginSession() throws {}

  func endSession() throws -> RecordingResult {
    RecordingResult(
      fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("noop.wav"),
      duration: 0.5
    )
  }
}

private final class AutoStartMockPostProcessService: PostProcessServicing {
  func cleanup(_ rawText: String, mode: TextCleanupMode) -> String {
    rawText
  }
}

private final class AutoStartMockFocusSafetyService: FocusSafetyServicing {
  func shouldBlockPaste(blockSecureInput: Bool) -> Bool {
    false
  }
}

private final class AutoStartMockPasteService: PasteServicing {
  func paste(_ text: String, restoreClipboard: Bool) throws {}
  func copyToClipboard(_ text: String) throws {}
}

private final class AutoStartMockModelManager: ModelManaging {
  func ensureModelInstalled(_ tier: ModelTier) async throws -> URL {
    URL(fileURLWithPath: "/tmp/mock-model.bin")
  }

  func ensureVADModelInstalled() async throws -> URL {
    URL(fileURLWithPath: "/tmp/mock-vad.bin")
  }

  func installedModels() async -> [ModelTier] {
    [.medium]
  }

  func removeModel(_ tier: ModelTier) async throws -> Bool {
    false
  }
}

private final class AutoStartMockTranscriptionService: TranscriptionServicing {
  func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult {
    TranscriptionResult(text: "noop", detectedLanguage: .en, durationMs: 0)
  }
}

private final class AutoStartMockWhisperServerManager: WhisperServerManaging {
  var isReady = true
  var baseURL: URL { URL(string: "http://127.0.0.1:8178")! }

  func start(modelPath: String, vadModelPath: String?) async throws {}
  func stop() {}
}

@MainActor
private final class AutoStartMockHUDController: HUDControlling {
  func show(
    state: PipelineState,
    message: String,
    duration: TimeInterval?,
    showsCompletionCheck: Bool
  ) {}

  func update(level: Float) {}

  func hide() {}
}
