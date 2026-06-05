import Foundation
import Testing
@testable import FridayMac

@MainActor
struct ModelRoutingPolicyTests {
  @Test
  func selectedMediumStaysOnMedium() {
    let controller = makeController()
    controller.settings.defaultModel = .medium
    controller.settings.installedModels = [.medium, .turbo]

    #expect(controller.resolveTranscriptionModel() == .medium)
  }

  @Test
  func selectedTurboUsesTurboWhenInstalled() {
    let controller = makeController()
    controller.settings.defaultModel = .turbo
    controller.settings.installedModels = [.medium, .turbo]

    #expect(controller.resolveTranscriptionModel() == .turbo)
  }

  @Test
  func routeFallsBackToMediumWhenDefaultNotInstalled() {
    let controller = makeController()
    controller.settings.defaultModel = .turbo
    controller.settings.installedModels = [.medium]

    #expect(controller.resolveTranscriptionModel() == .medium)
  }

  @Test
  func migratesLargeV3DefaultToTurboWhenInstalled() async {
    let controller = makeController()
    controller.settings.defaultModel = .largeV3
    controller.settings.installedModels = [.medium, .turbo]

    await controller.migrateAwayFromLargeV3IfNeeded()
    #expect(controller.settings.defaultModel == .turbo)
  }

  @Test
  func migratesLargeV3DefaultToMediumWhenTurboMissing() async {
    let controller = makeController()
    controller.settings.defaultModel = .largeV3
    controller.settings.installedModels = [.medium]

    await controller.migrateAwayFromLargeV3IfNeeded()
    #expect(controller.settings.defaultModel == .medium)
  }

  private func makeController(
    transcriptionService: RoutingTranscriptionService = RoutingTranscriptionService()
  ) -> FridayController {
    let settingsStore = RoutingSettingsStore()
    let controller = FridayController(
      dependencies: FridayDependencies(
        settingsStore: settingsStore,
        permissionService: RoutingPermissionService(),
        hotkeyService: RoutingHotkeyService(),
        audioCaptureService: RoutingAudioCaptureService(),
        postProcessService: RoutingPostProcessService(),
        focusSafetyService: RoutingFocusSafetyService(),
        pasteService: RoutingPasteService(),
        autoLaunchService: RoutingAutoLaunchService(),
        hudController: RoutingHUDController(),
        modelManager: RoutingModelManager(),
        transcriptionService: transcriptionService,
        whisperServer: RoutingWhisperServerManager(),
        fileManager: .default
      )
    )
    controller.settings = settingsStore.current
    return controller
  }
}

private final class RoutingSettingsStore: SettingsStoreControlling {
  var current = FridaySettings.default

  func load() async -> FridaySettings { current }

  func update(_ mutate: (inout FridaySettings) -> Void) async -> FridaySettings {
    mutate(&current)
    return current
  }
}

private final class RoutingPermissionService: PermissionServicing {
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

private final class RoutingHotkeyService: HotkeyServicing {
  var onPress: (() -> Void)?
  var onRelease: (() -> Void)?
  var isRunning: Bool = true

  func start() throws {}
  func stop() {}
}

private final class RoutingAudioCaptureService: AudioCaptureServicing {
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
      fileURL: URL(fileURLWithPath: "/tmp/mock.wav"),
      duration: 0.8
    )
  }
}

private final class RoutingPostProcessService: PostProcessServicing {
  func cleanup(_ rawText: String, mode: TextCleanupMode) -> String { rawText }
}

private final class RoutingFocusSafetyService: FocusSafetyServicing {
  func shouldBlockPaste(blockSecureInput: Bool) -> Bool { false }
}

private final class RoutingPasteService: PasteServicing {
  func paste(_ text: String, restoreClipboard: Bool) throws {}
  func copyToClipboard(_ text: String) throws {}
}

private final class RoutingAutoLaunchService: AutoLaunchServicing {
  func setEnabled(_ enabled: Bool) throws {}
}

private final class RoutingModelManager: ModelManaging {
  func ensureModelInstalled(_ tier: ModelTier) async throws -> URL {
    URL(fileURLWithPath: "/tmp/model-\(tier.rawValue).bin")
  }

  func ensureVADModelInstalled() async throws -> URL {
    URL(fileURLWithPath: "/tmp/vad.bin")
  }

  func installedModels() async -> [ModelTier] { [.medium] }

  func removeModel(_ tier: ModelTier) async throws -> Bool { false }
}

private final class RoutingTranscriptionService: TranscriptionServicing {
  var requests: [ModelTier] = []
  var handler: ((TranscriptionRequest) async throws -> TranscriptionResult)?

  func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult {
    requests.append(request.model)
    if let handler {
      return try await handler(request)
    }
    return TranscriptionResult(text: "noop", detectedLanguage: .unknown, durationMs: 0)
  }
}

private final class RoutingWhisperServerManager: WhisperServerManaging {
  var isReady = true
  var baseURL: URL { URL(string: "http://127.0.0.1:8178")! }

  func start(modelPath: String, vadModelPath: String?) async throws {}
  func restart() async throws {}
  func stop() {}
}

@MainActor
private final class RoutingHUDController: HUDControlling {
  func show(
    state: PipelineState,
    message: String,
    duration: TimeInterval?,
    showsCompletionCheck: Bool
  ) {}

  func update(level: Float) {}

  func hide() {}
}
