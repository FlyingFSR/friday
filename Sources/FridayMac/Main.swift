import AppKit

@main
enum FridayMain {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppLifecycleDelegate()
    app.delegate = delegate

    // Keep Dock icon visible per product decision.
    app.setActivationPolicy(.regular)
    // NSApplication.delegate is weak; keep a strong reference while runloop is active.
    withExtendedLifetime(delegate) {
      app.run()
    }
  }
}
