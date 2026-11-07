import AppKit
import SwiftUI

@MainActor
final class HUDWindowController {
  private let viewModel = HUDViewModel()
  private let panel: NSPanel
  private let hostingView: NSHostingView<HUDView>

  init() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 160, height: 34),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: true
    )
    panel.isReleasedWhenClosed = false
    // The window shadow follows the pill's opaque pixels, so it hugs the rounded shape.
    panel.hasShadow = true
    panel.level = .floating
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.ignoresMouseEvents = true

    let hostingView = NSHostingView(rootView: HUDView(model: viewModel))
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    panel.contentView = hostingView

    self.panel = panel
    self.hostingView = hostingView
  }

  func show(
    state: PipelineState,
    message: String,
    duration: TimeInterval?,
    showsCompletionCheck: Bool = false
  ) {
    if state == .recording, viewModel.state != .recording {
      viewModel.resetLevels()
    }
    viewModel.state = state
    viewModel.message = message
    viewModel.duration = duration
    viewModel.showsCompletionCheck = showsCompletionCheck

    resizePanelToFitContent()

    updatePanelFrameNearCursor()

    if !panel.isVisible {
      panel.orderFrontRegardless()
    }
  }

  func update(level: Float) {
    viewModel.push(level: level)
  }

  func hide() {
    viewModel.showsCompletionCheck = false
    panel.orderOut(nil)
  }

  private func resizePanelToFitContent() {
    hostingView.layoutSubtreeIfNeeded()
    let fitting = hostingView.fittingSize
    let targetWidth = ceil(fitting.width)
    let targetHeight = ceil(fitting.height)
    let current = panel.contentRect(forFrameRect: panel.frame).size

    guard abs(current.width - targetWidth) > 0.5 || abs(current.height - targetHeight) > 0.5 else {
      return
    }

    panel.setContentSize(NSSize(width: targetWidth, height: targetHeight))
    panel.invalidateShadow()
  }

  private func updatePanelFrameNearCursor() {
    let mouse = NSEvent.mouseLocation
    let size = panel.frame.size

    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else {
      panel.setFrameOrigin(NSPoint(x: mouse.x, y: mouse.y))
      return
    }

    let x = max(screen.visibleFrame.minX + 12, min(mouse.x + 16, screen.visibleFrame.maxX - size.width - 12))
    let y = max(screen.visibleFrame.minY + 12, min(mouse.y - size.height - 20, screen.visibleFrame.maxY - size.height - 12))
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}
