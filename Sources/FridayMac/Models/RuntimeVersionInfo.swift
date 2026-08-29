import Foundation

enum RuntimeVersionInfo {
  static let whisperVersionResourceName = "WHISPER_VERSION"

  static func normalizedWhisperCPPVersion(from contents: String?) -> String? {
    guard let contents else {
      return nil
    }

    let lines = contents
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    guard lines.count == 1 else {
      return nil
    }
    return lines[0]
  }

  static func whisperCPPVersion(in bundle: Bundle = .main) -> String? {
    guard let url = bundle.url(
      forResource: whisperVersionResourceName,
      withExtension: nil
    ), let contents = try? String(contentsOf: url, encoding: .utf8) else {
      return nil
    }
    return normalizedWhisperCPPVersion(from: contents)
  }

  static func diagnosticsSummary(whisperCPPVersion: String?) -> String {
    "Runtime version: whisper.cpp=\(whisperCPPVersion ?? "unavailable")"
  }
}
