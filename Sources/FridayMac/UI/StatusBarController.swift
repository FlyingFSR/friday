import AppKit
import Combine
import Foundation

@MainActor
final class StatusBarController: NSObject {
  private var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private weak var controller: FridayController?
  private var cancellables = Set<AnyCancellable>()
  private var healingTimer: Timer?
  private var rebuildCount = 0
  private let maxRebuildCount = 3

  init(controller: FridayController) {
    self.controller = controller
    super.init()

    configureStatusItem()
    bindPipelineState()
    startHealingTimer()
  }

  deinit {
    healingTimer?.invalidate()
    NSStatusBar.system.removeStatusItem(statusItem)
  }

  func ensureVisible() {
    statusItem.isVisible = true
    guard configureButtonIfPossible() else {
      rebuildStatusItem(reason: "button unavailable during ensureVisible")
      _ = configureButtonIfPossible()
      return
    }
  }

  private func configureStatusItem() {
    statusItem.length = NSStatusItem.variableLength
    statusItem.isVisible = true
    configureMenu()
    if !configureButtonIfPossible() {
      DispatchQueue.main.async { [weak self] in
        _ = self?.configureButtonIfPossible()
      }
    }
  }

  @discardableResult
  private func configureButtonIfPossible() -> Bool {
    guard let button = statusItem.button else {
      return false
    }

    button.title = ""
    button.imagePosition = .imageLeading
    button.toolTip = "Friday"
    updateIcon(for: controller?.pipelineState ?? .idle)
    return true
  }

  private func startHealingTimer() {
    healingTimer?.invalidate()
    healingTimer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.healIfNeeded()
      }
    }
    if let healingTimer {
      RunLoop.main.add(healingTimer, forMode: .common)
    }
  }

  private func healIfNeeded() {
    statusItem.isVisible = true

    guard let button = statusItem.button else {
      rebuildStatusItem(reason: "status button missing")
      return
    }

    let hasVisibleContent = button.image != nil || !button.title.isEmpty
    if !hasVisibleContent {
      if !configureButtonIfPossible() {
        rebuildStatusItem(reason: "status button had no visible content")
      }
    }
  }

  private func rebuildStatusItem(reason: String) {
    guard rebuildCount < maxRebuildCount else {
      return
    }
    rebuildCount += 1

    NSStatusBar.system.removeStatusItem(statusItem)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    configureStatusItem()
    NSLog("Friday status item rebuilt (%d/%d): %@", rebuildCount, maxRebuildCount, reason)
  }

  private func configureMenu() {
    let menu = NSMenu()

    let versionItem = NSMenuItem(title: "Friday \(AppInfo.versionLabel)", action: nil, keyEquivalent: "")
    versionItem.isEnabled = false
    menu.addItem(versionItem)
    menu.addItem(.separator())

    let openSetup = NSMenuItem(title: "Open Friday Setup", action: #selector(openSetupAssistant), keyEquivalent: "")
    openSetup.target = self

    let openComparison = NSMenuItem(title: "Model Settings", action: #selector(openSetupAssistant), keyEquivalent: "")
    openComparison.target = self

    let quitItem = NSMenuItem(title: "Quit Friday", action: #selector(quitFriday), keyEquivalent: "q")
    quitItem.target = self

    menu.addItem(openSetup)
    menu.addItem(openComparison)
    menu.addItem(.separator())
    menu.addItem(quitItem)

    statusItem.menu = menu
  }

  private func bindPipelineState() {
    controller?.$pipelineState
      .receive(on: RunLoop.main)
      .sink { [weak self] state in
        self?.updateIcon(for: state)
      }
      .store(in: &cancellables)
  }

  private func updateIcon(for state: PipelineState) {
    guard let button = statusItem.button else {
      return
    }

    let symbolName: String
    switch state {
    case .idle:
      symbolName = "mic"
    case .recording:
      symbolName = "waveform"
    case .transcribing:
      symbolName = "ellipsis.circle"
    case .pasted:
      symbolName = "checkmark.circle"
    case .error:
      symbolName = "exclamationmark.triangle"
    }

    if let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Friday") {
      icon.isTemplate = true
      button.title = "FR"
      button.image = icon
      button.imagePosition = .imageLeading
    } else {
      configureFallbackTitle()
    }
  }

  private func configureFallbackTitle() {
    guard let button = statusItem.button else {
      return
    }
    button.image = nil
    button.title = "FR"
    button.imagePosition = .noImage
    button.toolTip = "Friday"
  }

  @objc
  private func openSetupAssistant() {
    controller?.openSetupAssistant()
  }

  @objc
  private func quitFriday() {
    NSApplication.shared.terminate(nil)
  }
}
