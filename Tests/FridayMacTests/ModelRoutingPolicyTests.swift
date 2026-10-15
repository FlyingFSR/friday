import Foundation
import Qwen3ASR
import Testing
@testable import FridayMac

@MainActor
struct ModelRoutingPolicyTests {
  @Test
  func routesToQwenWhenInstalled() {
    let controller = makeController()
    controller.settings.defaultModel = .qwen3ASR
    controller.settings.installedModels = [.qwen3ASR]

    #expect(controller.resolveTranscriptionModel() == .qwen3ASR)
  }

  @Test
  func whisperDefaultRoutesToQwenWhenInstalled() {
    let controller = makeController()
    controller.settings.defaultModel = .medium
    controller.settings.installedModels = [.medium, .qwen3ASR]

    #expect(controller.resolveTranscriptionModel() == .qwen3ASR)
  }

  @Test
  func preferredModelIsNilWhenOnlyWhisperModelsRemain() {
    // A Friday 0.4 Whisper file on disk is not routable in 0.5; the policy returns nil
    // so the app prompts the user to install Qwen3-ASR.
    let preferred = FridayController.preferredTranscriptionModel(
      defaultModel: .medium,
      installedModels: [.medium, .turbo]
    )
    #expect(preferred == nil)
  }

  @Test
  func migratesWhisperDefaultsToQwen() async {
    for retired in [ModelTier.medium, .largeV3, .turbo, .base, .small] {
      let controller = makeController()
      controller.settings.defaultModel = retired
      controller.settings.installedModels = [.qwen3ASR]

      await controller.migrateAwayFromRetiredModelsIfNeeded()
      #expect(controller.settings.defaultModel == .qwen3ASR)
    }
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
        speechEngine: RoutingSpeechEngine(),
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

  func setSelectedHotkey(_ hotkey: PushToTalkKey) {}
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


  func installedModels() async -> [ModelTier] { [.qwen3ASR] }

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

private final class RoutingSpeechEngine: SpeechEngineControlling, @unchecked Sendable {
  var isLoaded: Bool {
    get async { true }
  }

  func load(modelDirectory: URL) async throws {}

  func transcribe(samples: [Float], language: String, context: String) async throws -> TranscriptionOutput {
    TranscriptionOutput(text: "", language: language, finishReasons: ["eos"])
  }
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
