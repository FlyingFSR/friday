import Foundation
import ServiceManagement

/// What macOS itself says about Friday's login item, independent of Friday's saved settings.
enum AutoLaunchSystemState: Equatable {
  /// macOS will open Friday at login.
  case enabled
  /// Friday is not a login item.
  case disabled
  /// Friday is registered, but the switch in System Settings > General > Login Items is off,
  /// so macOS will not open it until the user turns it on there.
  case requiresApproval
  /// macOS cannot tell, e.g. when running the bare binary from `.build` instead of Friday.app.
  case unknown
}

final class AutoLaunchService {
  func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }

  func systemState() -> AutoLaunchSystemState {
    switch SMAppService.mainApp.status {
    case .enabled:
      return .enabled
    case .notRegistered:
      return .disabled
    case .requiresApproval:
      return .requiresApproval
    case .notFound:
      return .unknown
    @unknown default:
      return .unknown
    }
  }

  func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
