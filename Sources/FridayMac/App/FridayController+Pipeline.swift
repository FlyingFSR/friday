import AppKit
import Foundation

extension FridayController {
  struct TranscriptionRouteDecision {
    let preferredModel: ModelTier
    let shouldScheduleLargeInstall: Bool
    let reason: String
  }

  func handleHotkeyDown() {
    guard pipelineState == .idle || pipelineState == .pasted || pipelineState == .error else {
      return
    }

    cancelPendingIdleReset()
    refreshPermissions()

    guard permissions.microphone else {
      fail(FridayError.microphonePermissionDenied.localizedDescription, sessionID: nil)
      return
    }

    originApp = NSWorkspace.shared.frontmostApplication

    if !permissions.inputMonitoring {
      inferredInputMonitoringGranted = true
      permissions.inputMonitoring = true
      log("Input monitoring inferred as granted (hotkey event received)")
      updateOnboardingRequirement()
    }

    do {
      try ensureContinuousCaptureReady()
      if !permissions.microphone {
        inferredMicrophoneGranted = true
        permissions.microphone = true
        log("Microphone inferred as granted (recording started)")
      }

      let sessionID = UUID()
      activeSessionID = sessionID
      recordingDuration = 0
      recordingLevel = 0
      pipelineState = .recording
      statusMessage = "Recording..."
      hudController.show(state: .recording, message: statusMessage, duration: recordingDuration, showsCompletionCheck: false)
      updateOnboardingRequirement()
      startRecordingTimer()
    } catch {
      fail(error.localizedDescription, sessionID: nil)
    }
  }

  func handleHotkeyUp() {
    guard pipelineState == .recording else {
      return
    }

    stopRecordingTimer()
    let sessionID = activeSessionID ?? UUID()
    activeSessionID = sessionID

    do {
      let recording = try audioCaptureService.endSession()
      if recording.duration < 0.25 {
        throw FridayError.recordingTooShort
      }

      pipelineState = .transcribing
      statusMessage = "Transcribing..."
      hudController.show(state: .transcribing, message: statusMessage, duration: nil, showsCompletionCheck: false)

      transcriptionTask?.cancel()
      transcriptionTask = Task { [weak self] in
        guard let self else { return }
        if Task.isCancelled { return }

        let wavPath = recording.fileURL.path
        var cleanupPaths: [String] = [wavPath]
        defer {
          self.cleanupTempFiles(cleanupPaths)
          if self.activeSessionID == sessionID {
            self.originApp = nil
          }
        }

        do {
          let routeDecision = self.decideTranscriptionRoute(
            recordingDuration: recording.duration,
            requestedLanguage: self.settings.transcriptionLanguage
          )

          let transcription: TranscriptionResult
          do {
            transcription = try await self.transcribeWithRouting(
              wavPath: wavPath,
              recordingDuration: recording.duration,
              routeDecision: routeDecision,
              cleanupPaths: &cleanupPaths
            )
            cleanupPaths.append(contentsOf: transcription.artifactPaths)
            if !transcription.diagnostics.isEmpty {
              self.log("Transcription diagnostics: \(transcription.diagnostics.joined(separator: " | "))")
            }
          } catch let failure as TranscriptionFailure {
            cleanupPaths.append(contentsOf: failure.artifactPaths)
            self.log("Transcription failure kind=\(failure.kind.rawValue) reason=\(failure.reason)")
            if !failure.diagnostics.isEmpty {
              self.log("Transcription diagnostics: \(failure.diagnostics.joined(separator: " | "))")
            }
            throw FridayError.transcriptionFailed(self.userFacingTranscriptionMessage(for: failure))
          }

          guard self.isSessionActive(sessionID) else {
            return
          }
          if Task.isCancelled { return }

          self.log("Raw transcript stats: \(self.transcriptScriptStats(transcription.text))")
          let cleaned = self.postProcessService.cleanup(transcription.text, mode: self.settings.textCleanup)
          self.log("Cleaned transcript stats: \(self.transcriptScriptStats(cleaned))")
          self.log("Applied cleanup mode: \(self.settings.textCleanup.rawValue)")

          if self.focusSafetyService.shouldBlockPaste(blockSecureInput: self.settings.blockSecureInput) {
            throw FridayError.secureInputEnabled
          }

          if !self.permissions.accessibility {
            self.startPermissionPolling(duration: 10)
            self.log("Accessibility preflight returned false; continuing without auto-prompt")
          }

          if let origin = self.originApp, !origin.isTerminated,
             origin.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier {
            origin.activate()
            try? await Task.sleep(nanoseconds: 150_000_000)
          }

          do {
            try self.pasteService.paste(cleaned, restoreClipboard: self.settings.pasteRestoreClipboard)
            let accessibilityNow = self.permissionService.accessibilityGranted()
            if accessibilityNow && !self.permissions.accessibility {
              self.inferredAccessibilityGranted = true
              self.permissions.accessibility = true
              self.log("Accessibility inferred as granted (paste succeeded)")
              self.updateOnboardingRequirement()
            }

            guard self.isSessionActive(sessionID) else {
              return
            }

            self.pipelineState = .pasted
            self.statusMessage = "Done"
            self.hudController.show(
              state: .pasted,
              message: "Done",
              duration: nil,
              showsCompletionCheck: true
            )
            self.log(
              "Transcribed and pasted: model=\(self.settings.defaultModel.rawValue), " +
              "lang=\(transcription.detectedLanguage.rawValue), durationMs=\(transcription.durationMs), " +
              "cleanup=\(self.settings.textCleanup.rawValue)"
            )
            self.scheduleIdleReset(seconds: 0.8, sessionID: sessionID)
          } catch {
            try self.pasteService.copyToClipboard(cleaned)
            guard self.isSessionActive(sessionID) else {
              return
            }

            self.pipelineState = .pasted
            self.statusMessage = "Copied to clipboard"
            self.hudController.show(
              state: .pasted,
              message: "Copied to clipboard",
              duration: nil,
              showsCompletionCheck: true
            )
            self.log("Paste failed, copied instead: \(error.localizedDescription)")
            self.scheduleIdleReset(seconds: 1.0, sessionID: sessionID)
          }
        } catch {
          guard self.isSessionActive(sessionID) else {
            return
          }
          self.fail(error.localizedDescription, sessionID: sessionID)
        }
      }
    } catch {
      fail(error.localizedDescription, sessionID: sessionID)
    }
  }

  func startRecordingTimer() {
    stopRecordingTimer()
    recordingTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.recordingDuration += 0.05
        self.hudController.show(
          state: .recording,
          message: self.statusMessage,
          duration: self.recordingDuration,
          showsCompletionCheck: false
        )
      }
    }
    if let recordingTimer {
      RunLoop.main.add(recordingTimer, forMode: .common)
    }
  }

  func stopRecordingTimer() {
    recordingTimer?.invalidate()
    recordingTimer = nil
  }

  func scheduleIdleReset(seconds: Double, sessionID: UUID?) {
    cancelPendingIdleReset()
    pendingIdleResetTask = Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      if Task.isCancelled {
        return
      }
      if let sessionID, self.activeSessionID != sessionID {
        return
      }

      self.pipelineState = .idle
      self.statusMessage = "Ready"
      self.recordingDuration = 0
      self.recordingLevel = 0
      self.hudController.hide()
      if let sessionID, self.activeSessionID == sessionID {
        self.activeSessionID = nil
      }
    }
  }

  func cancelPendingIdleReset() {
    pendingIdleResetTask?.cancel()
    pendingIdleResetTask = nil
  }

  func fail(_ message: String, sessionID: UUID?) {
    if let sessionID, !isSessionActive(sessionID) {
      return
    }

    pipelineState = .error
    statusMessage = message
    hudController.show(state: .error, message: message, duration: nil, showsCompletionCheck: false)
    log("Error: \(message)")
    scheduleIdleReset(seconds: 1.8, sessionID: sessionID)
  }

  func isSessionActive(_ sessionID: UUID) -> Bool {
    activeSessionID == sessionID
  }

  func cleanupTempFiles(_ paths: [String]) {
    for path in Set(paths) where !path.isEmpty {
      cleanupTempFile(at: path)
    }
  }

  func cleanupTempFile(at path: String) {
    try? fileManager.removeItem(atPath: path)
  }

  func userFacingTranscriptionMessage(for failure: TranscriptionFailure) -> String {
    switch failure.kind {
    case .chunkRetryFailed:
      return "Chunk retry failed."
    case .fallbackBudgetExceeded:
      return "Fallback recovery exceeded its time budget."
    case .singlePassFailed:
      return "Single-pass fallback failed."
    case .chunkingFailed:
      return "Chunked transcription failed."
    case .cancelled:
      return "Transcription was cancelled."
    case .unknown:
      return failure.reason
    }
  }

  func ensureContinuousCaptureReady() throws {
    if !audioCaptureService.isContinuousCaptureRunning {
      try audioCaptureService.startContinuousCapture()
    }

    do {
      try audioCaptureService.beginSession()
    } catch {
      // Recover once for transient engine interruptions.
      audioCaptureService.stopContinuousCapture()
      try audioCaptureService.startContinuousCapture()
      try audioCaptureService.beginSession()
    }
  }

  func decideTranscriptionRoute(
    recordingDuration: TimeInterval,
    requestedLanguage: String
  ) -> TranscriptionRouteDecision {
    let _ = recordingDuration
    let _ = requestedLanguage

    if settings.installedModels.contains(settings.defaultModel) {
      return TranscriptionRouteDecision(
        preferredModel: settings.defaultModel,
        shouldScheduleLargeInstall: false,
        reason: "route=\(settings.defaultModel.rawValue) selected-by-user"
      )
    }

    return TranscriptionRouteDecision(
      preferredModel: .medium,
      shouldScheduleLargeInstall: false,
      reason: "route=medium fallback-not-installed"
    )
  }

  func transcribeWithRouting(
    wavPath: String,
    recordingDuration: TimeInterval,
    routeDecision: TranscriptionRouteDecision,
    cleanupPaths: inout [String]
  ) async throws -> TranscriptionResult {
    let primaryRequest = TranscriptionRequest(
      wavPath: wavPath,
      model: routeDecision.preferredModel,
      language: settings.transcriptionLanguage,
      recordingDuration: recordingDuration
    )

    do {
      let primaryResult = try await transcriptionService.transcribe(request: primaryRequest)
      log("Transcription route primary=\(routeDecision.preferredModel.rawValue) reason=\(routeDecision.reason)")

      guard routeDecision.preferredModel == .largeV3,
            shouldAttemptQualityFallbackForLargeResult(
              primaryResult,
              recordingDuration: recordingDuration,
              requestedLanguage: settings.transcriptionLanguage
            ) else {
        return primaryResult
      }

      log("Large-v3 result looks language-locked, retrying medium once for quality fallback.")
      let fallbackRequest = TranscriptionRequest(
        wavPath: wavPath,
        model: .medium,
        language: settings.transcriptionLanguage,
        recordingDuration: recordingDuration
      )

      do {
        let fallbackResult = try await transcriptionService.transcribe(request: fallbackRequest)
        cleanupPaths.append(contentsOf: fallbackResult.artifactPaths)
        let preferFallback = shouldPreferFallbackTranscription(primary: primaryResult, fallback: fallbackResult)
        log("Large-v3 quality fallback completed: preferFallback=\(preferFallback)")
        if preferFallback {
          return TranscriptionResult(
            text: fallbackResult.text,
            detectedLanguage: fallbackResult.detectedLanguage,
            durationMs: fallbackResult.durationMs,
            artifactPaths: fallbackResult.artifactPaths,
            diagnostics: primaryResult.diagnostics + ["quality-fallback=medium-selected"] + fallbackResult.diagnostics
          )
        }
        return TranscriptionResult(
          text: primaryResult.text,
          detectedLanguage: primaryResult.detectedLanguage,
          durationMs: primaryResult.durationMs,
          artifactPaths: primaryResult.artifactPaths,
          diagnostics: primaryResult.diagnostics + ["quality-fallback=medium-rejected"] + fallbackResult.diagnostics
        )
      } catch let fallbackFailure as TranscriptionFailure {
        cleanupPaths.append(contentsOf: fallbackFailure.artifactPaths)
        log("Large-v3 quality fallback failed: \(fallbackFailure.reason)")
        return primaryResult
      }
    } catch let primaryFailure as TranscriptionFailure {
      cleanupPaths.append(contentsOf: primaryFailure.artifactPaths)
      guard routeDecision.preferredModel == .largeV3 else {
        throw primaryFailure
      }

      log("Large-v3 route failed, retrying medium once: \(primaryFailure.reason)")
      let fallbackRequest = TranscriptionRequest(
        wavPath: wavPath,
        model: .medium,
        language: settings.transcriptionLanguage,
        recordingDuration: recordingDuration
      )

      do {
        let fallbackResult = try await transcriptionService.transcribe(request: fallbackRequest)
        log("Fallback route succeeded: medium")
        return fallbackResult
      } catch let fallbackFailure as TranscriptionFailure {
        cleanupPaths.append(contentsOf: fallbackFailure.artifactPaths)
        let combinedDiagnostics = primaryFailure.diagnostics + fallbackFailure.diagnostics
        let combinedArtifacts = Array(Set(primaryFailure.artifactPaths + fallbackFailure.artifactPaths))
        throw TranscriptionFailure(
          kind: fallbackFailure.kind,
          reason: fallbackFailure.reason,
          artifactPaths: combinedArtifacts,
          diagnostics: combinedDiagnostics
        )
      }
    }
  }

  private func shouldAttemptQualityFallbackForLargeResult(
    _ result: TranscriptionResult,
    recordingDuration: TimeInterval,
    requestedLanguage: String
  ) -> Bool {
    let normalizedLanguage = requestedLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let resolvedLanguage = normalizedLanguage.isEmpty ? "auto" : normalizedLanguage
    guard resolvedLanguage == "auto", recordingDuration >= 25 else {
      return false
    }

    let (cjk, latin) = scriptCharacterCounts(in: result.text)
    if min(cjk, latin) == 0 {
      return true
    }

    return result.diagnostics.contains { line in
      line.contains("language-lock") || line.contains("global-en-lock") || line.contains("global-zh-lock")
    }
  }

  private func shouldPreferFallbackTranscription(
    primary: TranscriptionResult,
    fallback: TranscriptionResult
  ) -> Bool {
    let primaryCounts = scriptCharacterCounts(in: primary.text)
    let fallbackCounts = scriptCharacterCounts(in: fallback.text)
    let primaryMixed = min(primaryCounts.cjk, primaryCounts.latin)
    let fallbackMixed = min(fallbackCounts.cjk, fallbackCounts.latin)

    if primaryMixed == 0, fallbackMixed >= 20 {
      return true
    }
    if fallbackMixed >= primaryMixed + 12 {
      return true
    }

    let primarySignal = primaryCounts.cjk + primaryCounts.latin
    let fallbackSignal = fallbackCounts.cjk + fallbackCounts.latin
    return fallbackMixed >= primaryMixed + 6 && fallbackSignal >= Int(Double(primarySignal) * 0.9)
  }

  private func scriptCharacterCounts(in text: String) -> (cjk: Int, latin: Int) {
    var cjk = 0
    var latin = 0
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x4E00...0x9FFF, 0x3400...0x4DBF:
        cjk += 1
      case 0x0041...0x005A, 0x0061...0x007A:
        latin += 1
      default:
        continue
      }
    }
    return (cjk, latin)
  }
}
