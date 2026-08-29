import Foundation

final class TranscriptionService {
  private let whisperServer: any WhisperServerManaging
  private let modelManager: any ModelManaging
  // Evidence-tuned initial prompt ("P6" in the 2026-08 language-detection eval; see
  // docs/language-detection-findings-2026-08.md). Every part is load-bearing:
  // - The Chinese example sentence protects long Chinese audio; a bare brand list destroyed it.
  // - The single short English clause is the active ingredient for recognizing "Claude" and for
  //   keeping English audio from being mistranslated into Chinese.
  // - Longer English prose is not an upgrade: it makes Chinese audio get translated into English.
  // This prompt and the server's flag set were validated as one configuration (the server must
  // not be launched with "-mc 0", which disables the prompt outright). It is not free: measured
  // against the pre-change baseline it costs roughly 9% latency on short dictation and 23% on
  // long audio, and yields slightly more traditional characters. Details in the findings doc.
  // Do not edit casually — any change has to be re-validated against the full eval matrix.
  static let mixedLanguagePrompt =
    "Friday Codex Claude Fable relay Sol ChatGPT OpenAI Whisper whisper.cpp macOS Swift Git VAD React component " +
    "system prompt pull request voice input flow。" +
    "今天我用 Claude 写一个 React component，然后让 Codex review 这个 pull request。" +
    "I use Claude every day。"

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
        Self.joinTranscriptSegments(
          text.replacingOccurrences(of: Self.blankAudioMarker, with: "")
        )
      )
    )
    return cleaned
  }

  /// Reassemble whisper-server's per-segment output into one line.
  ///
  /// Friday runs the server with timestamps on (see WhisperServerManager.buildServerArguments),
  /// so the JSON `text` field arrives split across segments: newlines between them and stray
  /// double spaces where a segment already began with one. Every run of whitespace collapses to
  /// a single space, except between two CJK characters — Chinese needs no word separator, and an
  /// injected space would survive into the user's document.
  static func joinTranscriptSegments(_ text: String) -> String {
    var output = ""
    var pendingWhitespace = false

    for character in text {
      if character.isWhitespace {
        pendingWhitespace = !output.isEmpty
        continue
      }
      if pendingWhitespace {
        if let previous = output.last, !isCJKJoinable(previous) || !isCJKJoinable(character) {
          output.append(" ")
        }
        pendingWhitespace = false
      }
      output.append(character)
    }

    return output
  }

  /// Full-width punctuation that carries its own spacing, so a segment break next to it needs no
  /// space. A superset of the clause-ending set PostProcessService works with: brackets, quotes,
  /// ellipsis, dash and interpunct are included here because a segment can break at any of them,
  /// and an injected space there survives every downstream cleanup mode.
  private static let cjkJoinablePunctuation = Set("，。！？；：、「」『』（）《》〈〉【】…—·“”‘’")

  /// Characters that need no space around them when segments are rejoined.
  private static func isCJKJoinable(_ character: Character) -> Bool {
    CJKScript.isCJK(character) || cjkJoinablePunctuation.contains(character)
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
    let withoutEnglishTail = stripShortEnglishHallucinationTailAfterCJK(result)
    return stripTrailingChineseHallucination(withoutEnglishTail)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Closing full-width brackets and quotes are valid context in front of a hallucinated tail. A
  /// quoted clause can be the last thing the user actually said, and once joinTranscriptSegments has
  /// removed the segment break the tail sits directly behind the closing mark ("他说「就这样吧」谢谢观看"),
  /// where a plain CJK / sentence-punctuation context would miss it.
  private static let closingCJKPunctuation = #"」』）》〉】”’"#

  private static func stripShortEnglishHallucinationTailAfterCJK(_ text: String) -> String {
    let pattern = #"(?<=["# + CJKScript.regexCharacterClass + closingCJKPunctuation + #"])\s+(?:Thank you|Thanks for watching|you|Bye bye|Bye)[\s.!?。！？]*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return text
    }
    return regex.stringByReplacingMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text),
      withTemplate: ""
    )
  }

  private static let chineseOutroPhrases =
    "谢谢观看|謝謝觀看|感谢收看|感謝收看|感谢观看|感謝觀看|谢谢收看|謝謝收看|请订阅|請訂閱"

  /// Strip Chinese video-outro phrases whisper hallucinates from trailing silence
  /// (both Simplified and Traditional, since a mis-configured run can flip script).
  /// Gated like the English variants: the tail must follow sentence-ending
  /// punctuation or another CJK character, so it never fires on a standalone
  /// phrase. The full four-character outros are specific enough to strip even
  /// without preceding punctuation — the real-world case ("謝謝觀看" appended to a
  /// paragraph that ended with no punctuation at all) had none. A bare "谢谢" and
  /// "谢谢大家" are deliberately absent: both are ordinary ways to close a message.
  private static func stripTrailingChineseHallucination(_ text: String) -> String {
    // A comma-class separator before the tail is consumed along with it so no
    // dangling "，" is left behind; sentence-ending punctuation stays. The `+`
    // repetition catches whisper looping the same outro several times.
    let pattern = #"(?<=["# + CJKScript.regexCharacterClass + closingCJKPunctuation + #".!?。！？])\s*[，、；：]?\s*(?:(?:"#
      + chineseOutroPhrases + #")[\s，、；：.!?。！？]*)+$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let matchRange = Range(match.range, in: text) else {
      return text
    }

    // Never let stripping reduce the text to nothing but outro phrases: text
    // that is only "谢谢观看" (repeated or not) is what the user actually said.
    let remainder = String(text[..<matchRange.lowerBound])
    let residue = remainder.replacingOccurrences(
      of: #"(?:"# + chineseOutroPhrases + #")|[\s，、；：.!?。！？]"#,
      with: "",
      options: .regularExpression
    )
    guard !residue.isEmpty else {
      return text
    }
    return remainder
  }

  /// Remove Korean/Japanese-only runs that are whisper hallucination artifacts.
  /// The user speaks Chinese + English; Korean (Hangul) and Japanese (Hiragana/Katakana)
  /// characters appearing in isolation are always hallucinated.
  static func stripHallucinatedText(_ text: String) -> String {
    // Korean Hangul syllables/Jamo, then Japanese Hiragana/Katakana.
    let koreanClass = "\\u1100-\\u11FF\\u3130-\\u318F\\uAC00-\\uD7AF"
    let japaneseClass = "\\u3040-\\u309F\\u30A0-\\u30FF"

    let withoutKorean = stripScriptRuns(text, scriptClass: koreanClass)
    return stripScriptRuns(withoutKorean, scriptClass: japaneseClass)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Whitespace and punctuation whisper mixes into a hallucinated run. Consumed only where it sits
  /// strictly between two characters of that run's script — punctuation on the outside belongs to
  /// the surrounding sentence and has to survive. Full-width forms are included because whisper
  /// punctuates CJK hallucinations the CJK way.
  private static let hallucinationInteriorSeparators = "\\s.,!?，。！？、"

  /// Punctuation glued to the end of a run (no space between) closed the hallucinated sentence, so
  /// it goes with the run. Half-width ".!?" are included alongside the full-width forms: Korean
  /// hallucinations end in a plain "." far more often than in "。", and leaving it behind orphans a
  /// stray mark next to the surviving Chinese ("我说完了。." / "会议结束了。！我们下次再聊。").
  /// Leading punctuation is deliberately still not consumed: there it belongs to the clause in front.
  private static let hallucinationTrailingPunctuation = "，。！？、.!?"

  /// Remove every run of `scriptClass`, along with the whitespace hugging it, and rejoin the
  /// surviving fragments the way joinTranscriptSegments would: no space between two CJK-joinable
  /// characters, a single space otherwise. A run at either end leaves nothing behind — the caller's
  /// trim handles the edge.
  private static func stripScriptRuns(_ text: String, scriptClass: String) -> String {
    let pattern = "\\s*[\(scriptClass)](?:[\(hallucinationInteriorSeparators)]*[\(scriptClass)])*"
      + "[\(hallucinationTrailingPunctuation)]*\\s*"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return text
    }

    var result = text
    let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
    for match in matches.reversed() {
      guard let range = Range(match.range, in: result) else { continue }
      let previous = result[..<range.lowerBound].last
      let next = result[range.upperBound...].first
      result.replaceSubrange(range, with: joinerReplacing(previous: previous, next: next))
    }
    return result
  }

  private static func joinerReplacing(previous: Character?, next: Character?) -> String {
    guard let previous, let next else {
      return ""
    }
    return isCJKJoinable(previous) && isCJKJoinable(next) ? "" : " "
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
