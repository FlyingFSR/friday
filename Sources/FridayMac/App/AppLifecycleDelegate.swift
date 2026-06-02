import AppKit
import Foundation

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
  private let controller = FridayController()

  private let singleInstanceService = SingleInstanceService()
  private var isObservingActivationRequest = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    switch singleInstanceService.acquireLock() {
    case .acquired:
      break
    case .alreadyRunning:
      singleInstanceService.notifyExistingInstanceToActivate()
      NSApplication.shared.terminate(nil)
      return
    case let .failed(reason):
      // Keep launching to avoid silent startup failure when lock setup breaks.
      NSLog("Friday single-instance lock unavailable: %@", reason)
    }

    registerActivationObserverIfNeeded()
    controller.bootstrap()
  }

  func applicationWillTerminate(_ notification: Notification) {
    controller.shutdown()
    unregisterActivationObserverIfNeeded()
    singleInstanceService.releaseLock()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    controller.openSetupAssistant()
    return true
  }

  @objc
  private func handleActivationRequest(_ notification: Notification) {
    guard singleInstanceService.shouldAcceptActivation(notification.userInfo) else {
      NSLog("Friday ignored activation request with invalid token")
      return
    }
    controller.handleExternalActivationRequest()
  }

  private func registerActivationObserverIfNeeded() {
    guard !isObservingActivationRequest else { return }

    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(handleActivationRequest(_:)),
      name: .fridayActivateExisting,
      object: nil,
      suspensionBehavior: .deliverImmediately
    )
    isObservingActivationRequest = true
  }

  private func unregisterActivationObserverIfNeeded() {
    guard isObservingActivationRequest else { return }
    DistributedNotificationCenter.default().removeObserver(self, name: .fridayActivateExisting, object: nil)
    isObservingActivationRequest = false
  }
}
