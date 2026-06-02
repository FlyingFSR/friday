import Foundation

final class TranscriptionService {
  enum AutoDecodingMode: String {
    case balanced
    case retryConservative
  }

  private let whisperServer: any WhisperServerManaging
  private let modelManager: any ModelManaging
  private static let mixedLanguagePrompt =
    "Friday Codex Claude ChatGPT OpenAI Whisper whisper.cpp macOS Swift Git VAD React component " +
    "system prompt pull request voice input flow。" +
    "今天我用 Claude 写一个 React component，然后让 Codex review 这个 pull request。" +
    "Friday 的 voice input flow 里面有 system prompt、ChatGPT、OpenAI 和 macOS Swift demo。"

  private static let segmentationDurationThreshold: TimeInterval = 3.0
  private static let minimumSegmentDuration: Double = 0.5
  private static let silenceDetectNoise = "-30dB"
  private static let silenceDetectDuration = "0.4"
  private static let blankAudioMarker = "[BLANK_AUDIO]"

  init(whisperServer: any WhisperServerManaging, modelManager: any ModelManaging) {
    self.whisperServer = whisperServer
    self.modelManager = modelManager
  }

  func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult {
    let startedAt = Date()
    _ = try await modelManager.ensureModelInstalled(request.model)

    guard whisperServer.isReady else {
      throw TranscriptionFailure(reason: FridayError.whisperServerUnavailable.localizedDescription)
    }

    let normalizedLanguage = request.language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let resolvedLanguage = normalizedLanguage.isEmpty ? "auto" : normalizedLanguage

    // Keep the request path single-pass; optional VAD now runs inside whisper-server.
    let outputText = try await transcribeSingle(wavPath: request.wavPath, language: resolvedLanguage)

    let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw TranscriptionFailure(reason: "empty output")
    }

    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
    return TranscriptionResult(
      text: trimmed,
      detectedLanguage: LanguageDetector.detect(in: trimmed),
      durationMs: durationMs,
      diagnostics: []
    )
  }

  // MARK: - HTTP transcription

  private func transcribeSingle(wavPath: String, language: String) async throws -> String {
    let wavData = try Data(contentsOf: URL(fileURLWithPath: wavPath))
    return try await postToServer(wavData: wavData, language: language)
  }

  private func transcribeSegments(_ segmentPaths: [String], language: String) async throws -> [String] {
    try await withThrowingTaskGroup(of: (Int, String).self) { group in
      for (index, path) in segmentPaths.enumerated() {
        group.addTask {
          let wavData = try Data(contentsOf: URL(fileURLWithPath: path))
          let text = try await self.postToServer(wavData: wavData, language: language)
          return (index, text)
        }
      }

      var results = [(Int, String)]()
      for try await result in group {
        results.append(result)
      }
      return results.sorted { $0.0 < $1.0 }.map(\.1).filter { !$0.isEmpty }
    }
  }

  private func postToServer(wavData: Data, language: String) async throws -> String {
    let inferenceURL = whisperServer.baseURL.appendingPathComponent("inference")
    let boundary = UUID().uuidString

    var body = Data()
    appendFormField(&body, boundary: boundary, name: "file", filename: "audio.wav", contentType: "audio/wav", data: wavData)
    appendTextField(&body, boundary: boundary, name: "response_format", value: "json")
    appendTextField(&body, boundary: boundary, name: "language", value: language)
    appendTextField(&body, boundary: boundary, name: "temperature", value: "0.0")
    appendTextField(&body, boundary: boundary, name: "temperature_inc", value: "0.0")
    // Always send the brand-name biasing prompt. Previously this was gated
    // on language=="auto", which left zh/en modes without any "Claude" /
    // "Codex" hint — a major reason whisper produces "cloud" for "Claude".
    appendTextField(&body, boundary: boundary, name: "prompt", value: Self.mixedLanguagePrompt)
    body.append(Data("--\(boundary)--\r\n".utf8))

    var request = URLRequest(url: inferenceURL)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    request.timeoutInterval = 120

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw TranscriptionFailure(reason: "unexpected response type from whisper-server")
    }
    guard (200...299).contains(http.statusCode) else {
      let errorBody = String(data: data, encoding: .utf8) ?? ""
      throw TranscriptionFailure(reason: "whisper-server returned HTTP \(http.statusCode): \(errorBody)")
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let text = json["text"] as? String else {
      throw TranscriptionFailure(reason: "invalid JSON response from whisper-server")
    }

    let cleaned = Self.stripTrailingHallucination(
      Self.stripHallucinatedText(
        text
          .replacingOccurrences(of: Self.blankAudioMarker, with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
      )
    )
    return cleaned
  }

  /// Strip common trailing hallucination phrases that whisper produces from silence at the end of audio.
  /// Only strips when preceded by sentence-ending punctuation to avoid false positives.
  static func stripTrailingHallucination(_ text: String) -> String {
    let pattern = #"(?<=[.!?。！？])\s+(?:Thank you|Thanks for watching|you|Bye bye|Bye)[\s.!?。！？]*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return text
    }
    let result = regex.stringByReplacingMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text),
      withTemplate: ""
    )
    return stripShortEnglishHallucinationTailAfterCJK(result)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func stripShortEnglishHallucinationTailAfterCJK(_ text: String) -> String {
    let pattern = #"(?<=[\u4E00-\u9FFF\u3400-\u4DBF])\s+(?:Thank you|Thanks for watching|you|Bye bye|Bye)[\s.!?。！？]*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return text
    }
    return regex.stringByReplacingMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text),
      withTemplate: ""
    )
  }

  /// Remove Korean/Japanese-only runs that are whisper hallucination artifacts.
  /// The user speaks Chinese + English; Korean (Hangul) and Japanese (Hiragana/Katakana)
  /// characters appearing in isolation are always hallucinated.
  static func stripHallucinatedText(_ text: String) -> String {
    // Match runs of Korean Hangul syllables/Jamo and surrounding punctuation/spaces
    // Also match Japanese Hiragana/Katakana-only runs
    let koreanPattern = "[\\u1100-\\u11FF\\u3130-\\u318F\\uAC00-\\uD7AF\\s.,!?]+"
    let japanesePattern = "[\\u3040-\\u309F\\u30A0-\\u30FF\\s.,!?]+"

    var result = text
    if let koreanRegex = try? NSRegularExpression(pattern: koreanPattern) {
      let matches = koreanRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
      for match in matches.reversed() {
        if let range = Range(match.range, in: result) {
          let fragment = String(result[range])
          // Only strip if fragment contains actual Korean characters (not just spaces/punctuation)
          if fragment.unicodeScalars.contains(where: { isKorean($0) }) {
            result.removeSubrange(range)
          }
        }
      }
    }
    if let japaneseRegex = try? NSRegularExpression(pattern: japanesePattern) {
      let matches = japaneseRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
      for match in matches.reversed() {
        if let range = Range(match.range, in: result) {
          let fragment = String(result[range])
          if fragment.unicodeScalars.contains(where: { isJapaneseKana($0) }) {
            result.removeSubrange(range)
          }
        }
      }
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isKorean(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
      return true
    default:
      return false
    }
  }

  private static func isJapaneseKana(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3040...0x309F, 0x30A0...0x30FF:
      return true
    default:
      return false
    }
  }

  // MARK: - Multipart helpers

  private func appendFormField(_ body: inout Data, boundary: String, name: String, filename: String, contentType: String, data: Data) {
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
    body.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
    body.append(data)
    body.append(Data("\r\n".utf8))
  }

  private func appendTextField(_ body: inout Data, boundary: String, name: String, value: String) {
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
    body.append(Data("\(value)\r\n".utf8))
  }

  // MARK: - Silence-based segmentation

  private func splitAtSilence(wavPath: String) -> [String] {
    guard let ffmpegPath = resolveFfmpegBinary() else {
      return [wavPath]
    }

    let silenceTimestamps = detectSilence(ffmpegPath: ffmpegPath, wavPath: wavPath)
    guard silenceTimestamps.count >= 1 else {
      return [wavPath]
    }

    let splitPoints = silenceTimestamps.map { ($0.start + $0.end) / 2.0 }
    return splitWav(ffmpegPath: ffmpegPath, wavPath: wavPath, splitPoints: splitPoints)
  }

  private struct SilenceInterval {
    let start: Double
    let end: Double
  }

  private func detectSilence(ffmpegPath: String, wavPath: String) -> [SilenceInterval] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpegPath)
    process.arguments = [
      "-i", wavPath,
      "-af", "silencedetect=noise=\(Self.silenceDetectNoise):d=\(Self.silenceDetectDuration)",
      "-f", "null", "-"
    ]

    let stderrPipe = Pipe()
    process.standardError = stderrPipe
    process.standardOutput = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return []
    }

    guard process.terminationStatus == 0 else { return [] }

    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

    var intervals = [SilenceInterval]()
    var currentStart: Double?

    for line in stderrText.components(separatedBy: .newlines) {
      if let range = line.range(of: "silence_start: ") {
        let valueString = line[range.upperBound...]
        if let spaceIndex = valueString.firstIndex(of: " ") {
          currentStart = Double(valueString[..<spaceIndex])
        } else {
          currentStart = Double(valueString)
        }
      } else if line.contains("silence_end: "), let start = currentStart {
        if let range = line.range(of: "silence_end: ") {
          let rest = line[range.upperBound...]
          if let spaceIndex = rest.firstIndex(of: " ") {
            if let end = Double(rest[..<spaceIndex]) {
              intervals.append(SilenceInterval(start: start, end: end))
            }
          } else if let end = Double(rest) {
            intervals.append(SilenceInterval(start: start, end: end))
          }
        }
        currentStart = nil
      }
    }

    return intervals
  }

  private func splitWav(ffmpegPath: String, wavPath: String, splitPoints: [Double]) -> [String] {
    let boundaries = [0.0] + splitPoints
    let segments: [(start: Double, end: Double?)] = (0..<boundaries.count).map { i in
      let start = boundaries[i]
      let end: Double? = (i + 1 < boundaries.count) ? boundaries[i + 1] : nil
      return (start, end)
    }

    var paths = [String]()
    let tempDir = FileManager.default.temporaryDirectory

    for (index, segment) in segments.enumerated() {
      // Skip segments shorter than minimum duration to avoid hallucination
      if let end = segment.end, (end - segment.start) < Self.minimumSegmentDuration {
        continue
      }

      let outPath = tempDir.appendingPathComponent("friday-seg-\(UUID().uuidString)-\(index).wav").path
      let process = Process()
      process.executableURL = URL(fileURLWithPath: ffmpegPath)

      var args = ["-y", "-i", wavPath, "-ss", String(format: "%.3f", segment.start)]
      if let end = segment.end {
        args.append(contentsOf: ["-to", String(format: "%.3f", end)])
      }
      args.append(contentsOf: ["-c", "copy", outPath])
      process.arguments = args
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice

      do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0, FileManager.default.fileExists(atPath: outPath) {
          paths.append(outPath)
        }
      } catch {
        continue
      }
    }

    return paths.isEmpty ? [wavPath] : paths
  }

  private func resolveFfmpegBinary() -> String? {
    let candidates = [
      "/opt/homebrew/bin/ffmpeg",
      "/usr/local/bin/ffmpeg"
    ]
    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
      return candidate
    }
    return nil
  }

  // MARK: - Legacy CLI arguments (kept for test compatibility)

  static func buildWhisperArguments(
    modelPath: String,
    wavPath: String,
    language: String,
    outputBasePath: String,
    autoMode: AutoDecodingMode = .balanced,
    promptContext: String? = nil,
    includeJSONOutput: Bool = false
  ) -> [String] {
    let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let resolvedLanguage = normalizedLanguage.isEmpty ? "auto" : normalizedLanguage

    var arguments = [
      "-m", modelPath,
      "-f", wavPath,
      "--no-timestamps",
      "--output-txt",
      "--output-file", outputBasePath,
      "--max-len", "0",
      "-et", "2.4",
      "-lpt", "-1.0"
    ]

    if resolvedLanguage == "auto" {
      arguments.append(contentsOf: [
        "-l", "auto",
        "-sow"
      ])

      switch autoMode {
      case .balanced:
        arguments.append(contentsOf: [
          "-mc", "0",
          "--prompt", mixedLanguagePrompt
        ])
      case .retryConservative:
        arguments.append(contentsOf: [
          "-mc", "-1",
          "--prompt", mixedLanguagePrompt
        ])
      }
    } else {
      arguments.append(contentsOf: ["-l", resolvedLanguage])
    }

    if includeJSONOutput {
      arguments.append(contentsOf: ["-oj", "-ojf"])
    }

    return arguments
  }
}
