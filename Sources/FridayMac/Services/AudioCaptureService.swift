import AVFoundation
import Foundation

struct RecordingResult {
  let fileURL: URL
  let duration: TimeInterval
}

final class AudioCaptureService: NSObject {
  private let queue = DispatchQueue(label: "Friday.AudioCaptureService")

  private var recorder: AVAudioRecorder?
  private var levelTimer: DispatchSourceTimer?
  private var currentFileURL: URL?
  private var recordingStartDate: Date?

  var onLevelUpdate: ((Float) -> Void)?

  // Kept for protocol compatibility. "Running" now means armed, not sampling.
  var isContinuousCaptureRunning: Bool {
    queue.sync { isArmed }
  }

  private var isArmed = false

  func startContinuousCapture() throws {
    queue.sync {
      isArmed = true
    }
  }

  func stopContinuousCapture() {
    let levelCallback = onLevelUpdate
    queue.sync {
      stopActiveRecordingLocked()
      isArmed = false
    }

    DispatchQueue.main.async {
      levelCallback?(0)
    }
  }

  func beginSession() throws {
    try queue.sync {
      guard isArmed else {
        throw FridayError.recordingNotActive
      }
      guard recorder?.isRecording != true else {
        throw FridayError.recordingAlreadyActive
      }

      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("friday-recordings", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

      let fileURL = directory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("wav")

      let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false
      ]

      let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
      recorder.isMeteringEnabled = true
      recorder.prepareToRecord()

      guard recorder.record() else {
        throw FridayError.recordingNotActive
      }

      self.recorder = recorder
      currentFileURL = fileURL
      recordingStartDate = Date()
      startLevelTimerLocked(recorder)
    }
  }

  func endSession() throws -> RecordingResult {
    try queue.sync {
      guard let recorder,
            recorder.isRecording,
            let fileURL = currentFileURL else {
        throw FridayError.recordingNotActive
      }

      recorder.stop()
      stopLevelTimerLocked()

      let startedAt = recordingStartDate ?? Date()
      let duration = max(0, Date().timeIntervalSince(startedAt))

      self.recorder = nil
      currentFileURL = nil
      recordingStartDate = nil

      let levelCallback = onLevelUpdate
      DispatchQueue.main.async {
        levelCallback?(0)
      }

      return RecordingResult(fileURL: fileURL, duration: duration)
    }
  }

  deinit {
    stopContinuousCapture()
  }

  private func startLevelTimerLocked(_ recorder: AVAudioRecorder) {
    stopLevelTimerLocked()

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(60))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      guard recorder.isRecording else { return }

      recorder.updateMeters()
      let averagePower = recorder.averagePower(forChannel: 0)
      let level = self.normalizedLevel(from: averagePower)

      DispatchQueue.main.async { [weak self] in
        self?.onLevelUpdate?(level)
      }
    }

    levelTimer = timer
    timer.resume()
  }

  private func stopLevelTimerLocked() {
    levelTimer?.cancel()
    levelTimer = nil
  }

  private func stopActiveRecordingLocked() {
    if let recorder, recorder.isRecording {
      recorder.stop()
    }
    stopLevelTimerLocked()

    recorder = nil
    currentFileURL = nil
    recordingStartDate = nil
  }

  private func normalizedLevel(from decibels: Float) -> Float {
    if decibels <= -80 {
      return 0
    }

    let floorDb: Float = -60
    let clamped = max(floorDb, decibels)
    let normalized = (clamped - floorDb) / abs(floorDb)
    return max(0, min(1, normalized))
  }
}
