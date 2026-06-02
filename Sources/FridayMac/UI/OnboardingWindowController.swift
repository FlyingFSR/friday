import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
  private let window: NSWindow

  init(controller: FridayController) {
    let contentView = OnboardingView(controller: controller)

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Friday Setup"
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 680, height: 560)
    window.center()
    window.contentView = NSHostingView(rootView: contentView)
  }

  func show() {
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func hide() {
    window.orderOut(nil)
  }
}
