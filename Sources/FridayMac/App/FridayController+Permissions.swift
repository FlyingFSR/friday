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
      } catch {
        // Registration fails when macOS still needs the user's approval; that case is handled
        // below from the system state, so only report other failures here.
        if autoLaunchService.systemState() != .requiresApproval {
          statusMessage = "Couldn't change Start at Login: \(error.localizedDescription)"
          log("Failed to set auto-start: \(error.localizedDescription)")
          return
        }
      }

      var effective = enabled
      switch autoLaunchService.systemState() {
      case .enabled:
        effective = true
      case .disabled:
        effective = false
      case .requiresApproval:
        effective = false
        if enabled {
          autoLaunchService.openLoginItemsSettings()
          statusMessage = "Turn on Friday in System Settings > Login Items to start it at login."
        }
      case .unknown:
        break
      }

      let updated = await settingsStore.update { settings in
        settings.autoStart = effective
      }
      settings = updated
      log("Auto-start set to \(effective) (requested \(enabled))")
    }
  }

  /// Makes the saved Start at Login setting match what macOS will actually do, in case the user
  /// changed it in System Settings > Login Items while Friday was not looking.
  func syncAutoStartWithSystem() async {
    let systemEnabled: Bool
    switch autoLaunchService.systemState() {
    case .enabled:
      systemEnabled = true
    case .disabled, .requiresApproval:
      systemEnabled = false
    case .unknown:
      return
    }
    guard settings.autoStart != systemEnabled else {
      return
    }
    let updated = await settingsStore.update { settings in
      settings.autoStart = systemEnabled
    }
    settings = updated
    log("Auto-start synced from system: \(systemEnabled)")
  }

  func setPushToTalkKey(_ hotkey: PushToTalkKey) {
    guard settings.pushToTalkKey != hotkey else {
      return
    }

    Task {
      let updated = await settingsStore.update { settings in
        settings.pushToTalkKey = hotkey
      }
      hotkeyService.setSelectedHotkey(hotkey)
      settings = updated
      log("Push-to-talk key set to \(hotkey.rawValue)")
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
