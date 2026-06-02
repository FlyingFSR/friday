import Foundation

enum FridayError: Error, LocalizedError {
  case microphonePermissionDenied
  case accessibilityPermissionDenied
  case inputMonitoringPermissionDenied
  case hotkeyTapUnavailable
  case recordingAlreadyActive
  case recordingNotActive
  case recordingTooShort
  case transcriptionFailed(String)
  case modelNotFound
  case modelChecksumUnavailable(String)
  case modelDownloadFailed(String)
  case secureInputEnabled
  case pasteFailed
  case whisperServerNotFound
  case whisperServerStartFailed
  case whisperServerUnavailable

  var errorDescription: String? {
    switch self {
    case .microphonePermissionDenied:
      return "Microphone permission is required."
    case .accessibilityPermissionDenied:
      return "Accessibility permission is required for paste automation."
    case .inputMonitoringPermissionDenied:
      return "Input Monitoring permission is required for global hotkey capture."
    case .hotkeyTapUnavailable:
      return "Failed to install global hotkey event tap."
    case .recordingAlreadyActive:
      return "Recording is already active."
    case .recordingNotActive:
      return "Recording is not active."
    case .recordingTooShort:
      return "Recording was too short."
    case .transcriptionFailed(let reason):
      return "Transcription failed: \(reason)"
    case .modelNotFound:
      return "Model descriptor not found."
    case .modelChecksumUnavailable(let model):
      return "Model checksum is unavailable or invalid for \(model)."
    case .modelDownloadFailed(let reason):
      return "Model download failed: \(reason)"
    case .secureInputEnabled:
      return "Secure input is active. Paste blocked."
    case .pasteFailed:
      return "Failed to paste transcription."
    case .whisperServerNotFound:
      return "whisper-server not found. Install whisper.cpp first."
    case .whisperServerStartFailed:
      return "whisper-server failed to start within timeout."
    case .whisperServerUnavailable:
      return "whisper-server is not running."
    }
  }
}
