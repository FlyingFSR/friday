import AppKit
import Foundation

protocol SettingsStoreControlling: AnyObject {
  func load() async -> FridaySettings
  func update(_ mutate: (inout FridaySettings) -> Void) async -> FridaySettings
}

protocol PermissionServicing: AnyObject {
  func snapshot() -> PermissionSnapshot
  func microphoneGranted() -> Bool
  func requestMicrophone() async -> Bool
  func accessibilityGranted() -> Bool
  func requestAccessibilityPrompt() -> Bool
  func inputMonitoringGranted() -> Bool
  func requestInputMonitoringPrompt() -> Bool
  func openMicrophoneSettings()
  func openAccessibilitySettings()
  func openInputMonitoringSettings()
}

protocol HotkeyServicing: AnyObject {
  var onPress: (() -> Void)? { get set }
  var onRelease: (() -> Void)? { get set }
  var isRunning: Bool { get }
  func start() throws
  func stop()
}

protocol AudioCaptureServicing: AnyObject {
  var isContinuousCaptureRunning: Bool { get }
  var onLevelUpdate: ((Float) -> Void)? { get set }
  func startContinuousCapture() throws
  func stopContinuousCapture()
  func beginSession() throws
  func endSession() throws -> RecordingResult
}

protocol PostProcessServicing: AnyObject {
  func cleanup(_ rawText: String, mode: TextCleanupMode) -> String
}

protocol FocusSafetyServicing: AnyObject {
  func shouldBlockPaste(blockSecureInput: Bool) -> Bool
}

protocol PasteServicing: AnyObject {
  func paste(_ text: String, restoreClipboard: Bool) throws
  func copyToClipboard(_ text: String) throws
}

protocol AutoLaunchServicing: AnyObject {
  func setEnabled(_ enabled: Bool) throws
}

protocol ModelManaging: AnyObject {
  func ensureModelInstalled(_ tier: ModelTier) async throws -> URL
  func ensureVADModelInstalled() async throws -> URL
  func installedModels() async -> [ModelTier]
  func removeModel(_ tier: ModelTier) async throws -> Bool
}

protocol TranscriptionServicing: AnyObject {
  func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult
}

protocol WhisperServerManaging: AnyObject {
  var isReady: Bool { get }
  var baseURL: URL { get }
  func start(modelPath: String, vadModelPath: String?) async throws
  func stop()
}

@MainActor
protocol HUDControlling: AnyObject {
  func show(
    state: PipelineState,
    message: String,
    duration: TimeInterval?,
    showsCompletionCheck: Bool
  )
  func update(level: Float)
  func hide()
}

struct FridayDependencies {
  let settingsStore: any SettingsStoreControlling
  let permissionService: any PermissionServicing
  let hotkeyService: any HotkeyServicing
  let audioCaptureService: any AudioCaptureServicing
  let postProcessService: any PostProcessServicing
  let focusSafetyService: any FocusSafetyServicing
  let pasteService: any PasteServicing
  let autoLaunchService: any AutoLaunchServicing
  let hudController: any HUDControlling
  let modelManager: any ModelManaging
  let transcriptionService: any TranscriptionServicing
  let whisperServer: any WhisperServerManaging
  let fileManager: FileManager

  @MainActor
  static func live() -> FridayDependencies {
    let settingsStore = SettingsStore()
    let modelManager = ModelManager(settingsStore: settingsStore)
    let whisperServer = WhisperServerManager()
    let transcriptionService = TranscriptionService(whisperServer: whisperServer, modelManager: modelManager)

    return FridayDependencies(
      settingsStore: settingsStore,
      permissionService: PermissionService(),
      hotkeyService: HotkeyService(),
      audioCaptureService: AudioCaptureService(),
      postProcessService: PostProcessService(),
      focusSafetyService: FocusSafetyService(),
      pasteService: PasteService(),
      autoLaunchService: AutoLaunchService(),
      hudController: HUDWindowController(),
      modelManager: modelManager,
      transcriptionService: transcriptionService,
      whisperServer: whisperServer,
      fileManager: .default
    )
  }
}

extension SettingsStore: SettingsStoreControlling {}
extension PermissionService: PermissionServicing {}
extension HotkeyService: HotkeyServicing {}
extension AudioCaptureService: AudioCaptureServicing {}
extension PostProcessService: PostProcessServicing {}
extension FocusSafetyService: FocusSafetyServicing {}
extension PasteService: PasteServicing {}
extension AutoLaunchService: AutoLaunchServicing {}
extension ModelManager: ModelManaging {}
extension TranscriptionService: TranscriptionServicing {}
extension HUDWindowController: HUDControlling {}
