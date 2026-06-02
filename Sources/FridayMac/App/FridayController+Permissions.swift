import Foundation

extension FridayController {
  func refreshPermissions() {
    let snapshot = permissionService.snapshot()
    if hotkeyService.isRunning, !snapshot.inputMonitoring {
      if !loggedInputMonitoringPreflightMismatch {
        log("Input Monitoring preflight is false while hotkey service is running; keeping preflight as source of truth.")
        loggedInputMonitoringPreflightMismatch = true
      }
    } else {
      loggedInputMonitoringPreflightMismatch = false
    }

    let latest = PermissionSnapshot(
      microphone: snapshot.microphone || inferredMicrophoneGranted,
      accessibility: snapshot.accessibility || inferredAccessibilityGranted,
      inputMonitoring: snapshot.inputMonitoring || inferredInputMonitoringGranted
    )

    if latest != permissions {
      permissions = latest
      log("Permissions: mic=\(permissions.microphone), ax=\(permissions.accessibility), input=\(permissions.inputMonitoring)")
      return
    }
    permissions = latest
  }

  func requestMicrophoneAccess() {
    Task {
      let granted = await permissionService.requestMicrophone()
      if granted {
        inferredMicrophoneGranted = true
      }
      refreshPermissions()
      startHotkeyIfPossible()
      startPermissionPolling(duration: 8)
      updateOnboardingRequirement()
    }
  }

  func requestAccessibilityAccess() {
    let granted = permissionService.requestAccessibilityPrompt()
    if granted {
      inferredAccessibilityGranted = true
    }
    refreshPermissions()
    startPermissionPolling(duration: 10)
    updateOnboardingRequirement()
  }

  func requestInputMonitoringAccess() {
    let granted = permissionService.requestInputMonitoringPrompt()
    if granted {
      inferredInputMonitoringGranted = true
    }
    refreshPermissions()
    startHotkeyIfPossible()
    startPermissionPolling(duration: 12)
    updateOnboardingRequirement()
  }

  func openMicrophoneSettings() {
    permissionService.openMicrophoneSettings()
    startPermissionPolling(duration: 12)
  }

  func openAccessibilitySettings() {
    permissionService.openAccessibilitySettings()
    startPermissionPolling(duration: 12)
  }

  func openInputMonitoringSettings() {
    permissionService.openInputMonitoringSettings()
    startPermissionPolling(duration: 12)
  }

  func setAutoStart(_ enabled: Bool) {
    Task {
      do {
        try autoLaunchService.setEnabled(enabled)
        let updated = await settingsStore.update { settings in
          settings.autoStart = enabled
        }
        settings = updated
        log("Auto-start set to \(enabled)")
      } catch {
        log("Failed to set auto-start: \(error.localizedDescription)")
      }
    }
  }

  func startHotkeyIfPossible() {
    do {
      try hotkeyService.start()
      if hotkeyService.isRunning, !permissionService.inputMonitoringGranted(),
         !loggedInputMonitoringPreflightMismatch {
        log("Hotkey service active but Input Monitoring preflight is still false.")
        loggedInputMonitoringPreflightMismatch = true
      }
    } catch {
      permissions.inputMonitoring = permissionService.inputMonitoringGranted() || inferredInputMonitoringGranted
      log("Hotkey unavailable: \(error.localizedDescription)")
    }
  }
}
