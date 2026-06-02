import AVFoundation
import AppKit
import ApplicationServices
import Foundation

struct PermissionSnapshot: Equatable {
  var microphone: Bool
  var accessibility: Bool
  var inputMonitoring: Bool

  var allGranted: Bool {
    microphone && accessibility && inputMonitoring
  }
}

final class PermissionService {
  func snapshot() -> PermissionSnapshot {
    PermissionSnapshot(
      microphone: microphoneGranted(),
      accessibility: accessibilityGranted(),
      inputMonitoring: inputMonitoringGranted()
    )
  }

  func microphoneGranted() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
  }

  func requestMicrophone() async -> Bool {
    await withCheckedContinuation { continuation in
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        continuation.resume(returning: granted)
      }
    }
  }

  func accessibilityGranted() -> Bool {
    AXIsProcessTrusted() || CGPreflightPostEventAccess()
  }

  func requestAccessibilityPrompt() -> Bool {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: true] as CFDictionary
    let axTrusted = AXIsProcessTrustedWithOptions(options)
    let postEventTrusted = CGRequestPostEventAccess()
    return axTrusted || postEventTrusted || accessibilityGranted()
  }

  func inputMonitoringGranted() -> Bool {
    CGPreflightListenEventAccess()
  }

  func requestInputMonitoringPrompt() -> Bool {
    CGRequestListenEventAccess()
  }

  func openMicrophoneSettings() {
    openSettingsPane(anchor: "Privacy_Microphone")
  }

  func openAccessibilitySettings() {
    openSettingsPane(anchor: "Privacy_Accessibility")
  }

  func openInputMonitoringSettings() {
    openSettingsPane(anchor: "Privacy_ListenEvent")
  }

  private func openSettingsPane(anchor: String) {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
