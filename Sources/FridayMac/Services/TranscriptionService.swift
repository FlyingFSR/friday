import Foundation

final class TranscriptionService {
  private let whisperServer: any WhisperServerManaging
  private let modelManager: any ModelManaging
  private static let mixedLanguagePrompt =
    "Friday Codex Claude ChatGPT OpenAI Whisper whisper.cpp macOS Swift Git VAD React component " +
    "system prompt pull request voice input flow。" +
    "今天我用 Claude 写一个 React component，然后让 Codex review 这个 pull request。" +
    "Friday 的 voice input flow 里面有 system prompt、ChatGPT、OpenAI 和 macOS Swift demo。"

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
    let pattern = #"(?<=["# + CJKScript.regexCharacterClass + #"])\s+(?:Thank you|Thanks for watching|you|Bye bye|Bye)[\s.!?。！？]*$"#
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
}
