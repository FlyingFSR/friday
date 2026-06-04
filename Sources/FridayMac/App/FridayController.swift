import AppKit
import Foundation
import SwiftUI

@MainActor
final class FridayController: ObservableObject {
  @Published var settings: FridaySettings = .default
  @Published var permissions = PermissionSnapshot(microphone: false, accessibility: false, inputMonitoring: false)
  @Published var pipelineState: PipelineState = .idle
  @Published var statusMessage: String = "Ready"
  @Published var recordingDuration: TimeInterval = 0
  @Published var recordingLevel: Float = 0
  @Published var requiresOnboarding: Bool = true
  @Published var diagnostics: [String] = []
  @Published var downloadingModel: ModelTier?

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
  let diagnosticsLogURL: URL

  var recordingTimer: Timer?
  var onboardingWindowController: OnboardingWindowController?
  var statusBarController: StatusBarController?
  var didBecomeActiveObserver: NSObjectProtocol?
  var permissionPollingTask: Task<Void, Never>?
  var pendingIdleResetTask: Task<Void, Never>?
  var transcriptionTask: Task<Void, Never>?
  var inferredMicrophoneGranted = false
  var inferredAccessibilityGranted = false
  var inferredInputMonitoringGranted = false
  var didAutoPresentOnboardingThisSession = false
  var hasBootstrapped = false
  var originApp: NSRunningApplication?
  var activeSessionID: UUID?
  var loggedInputMonitoringPreflightMismatch = false

  convenience init() {
    self.init(dependencies: .live())
  }

  init(dependencies: FridayDependencies) {
    settingsStore = dependencies.settingsStore
    permissionService = dependencies.permissionService
    hotkeyService = dependencies.hotkeyService
    audioCaptureService = dependencies.audioCaptureService
    postProcessService = dependencies.postProcessService
    focusSafetyService = dependencies.focusSafetyService
    pasteService = dependencies.pasteService
    autoLaunchService = dependencies.autoLaunchService
    hudController = dependencies.hudController
    modelManager = dependencies.modelManager
    transcriptionService = dependencies.transcriptionService
    whisperServer = dependencies.whisperServer
    fileManager = dependencies.fileManager
    let appSupportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    diagnosticsLogURL = appSupportRoot
      .appendingPathComponent("Friday", isDirectory: true)
      .appendingPathComponent("Logs", isDirectory: true)
      .appendingPathComponent("diagnostics.log")
    prepareDiagnosticsLogFileIfNeeded()

    hotkeyService.onPress = { [weak self] in
      Task { @MainActor in
        self?.handleHotkeyDown()
      }
    }

    hotkeyService.onRelease = { [weak self] in
      Task { @MainActor in
        self?.handleHotkeyUp()
      }
    }

    audioCaptureService.onLevelUpdate = { [weak self] level in
      Task { @MainActor in
        self?.recordingLevel = level
        self?.hudController.update(level: level)
      }
    }
  }
}
