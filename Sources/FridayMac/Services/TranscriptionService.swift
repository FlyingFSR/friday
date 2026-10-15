import Foundation
import Qwen3ASR

final class TranscriptionService {
  private let speechEngine: any SpeechEngineControlling
  private let modelManager: any ModelManaging

  /// Hot words passed to Qwen3-ASR as context. Same vocabulary as the Whisper prompt Friday used
  /// through 0.4, without its example sentences (those were Whisper-specific). Measured in
  /// docs/qwen3-asr-eval-2026-10.md: with the language forced to Chinese, these lift name accuracy
  /// without causing translation; they can occasionally pull a similar-sounding word toward a hot
  /// word (Cursor -> Claude once in 41 recordings).
  static let hotWords =
    "Friday Codex Claude Fable relay Sol ChatGPT OpenAI DeepSeek Qwen 通义千问 Haiku Whisper whisper.cpp " +
    "macOS Swift Git VAD React component system prompt pull request voice input flow"

  private static let blankAudioMarker = "[BLANK_AUDIO]"

  init(speechEngine: any SpeechEngineControlling, modelManager: any ModelManaging) {
    self.speechEngine = speechEngine
    self.modelManager = modelManager
  }

  func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult {
    let startedAt = Date()
    let modelDirectory = try await modelManager.ensureModelInstalled(request.model)
    try await speechEngine.load(modelDirectory: modelDirectory)

    let wavData = try Data(contentsOf: URL(fileURLWithPath: request.wavPath))
    guard let audio = PCM16Audio(wavData: wavData), audio.sampleRate == 16_000 else {
      throw TranscriptionFailure(reason: "recording is not 16 kHz mono 16-bit PCM")
    }

    let output = try await speechEngine.transcribe(
      samples: audio.floatSamples,
      language: Self.engineLanguage(for: request.language),
      context: Self.hotWords
    )
    let diagnostics = output.finishReasons.contains("length")
      ? ["engine stopped at the token limit (finish=\(output.finishReasons.joined(separator: ",")))"]
      : []

    let trimmed = Self.cleanTranscript(output.text)
    guard !trimmed.isEmpty else {
      throw TranscriptionFailure(reason: "empty output", diagnostics: diagnostics)
    }

    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
    return TranscriptionResult(
      text: trimmed,
      detectedLanguage: LanguageDetector.detect(in: trimmed),
      durationMs: durationMs,
      diagnostics: diagnostics
    )
  }

  /// Qwen3-ASR must be told the language: left to detect it, it translated Chinese inside mixed
  /// dictation into English (docs/qwen3-asr-eval-2026-10.md). "Chinese" still keeps English
  /// sentences in English. Only an explicit English setting selects English.
  static func engineLanguage(for setting: String) -> String {
    switch setting.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "en", "english":
      return "English"
    default:
      return "Chinese"
    }
  }

  /// Collapses stray whitespace and strips the hallucination patterns Whisper produced. Kept as a
  /// cheap safety net for the Qwen3-ASR engine until real use shows whether it is still needed.
  static func cleanTranscript(_ text: String) -> String {
    stripTrailingHallucination(
      stripHallucinatedText(
        joinTranscriptSegments(
          text.replacingOccurrences(of: blankAudioMarker, with: "")
        )
      )
    ).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Collapse every run of whitespace to a single space, except between two CJK characters —
  /// Chinese needs no word separator, and an injected space would survive into the user's
  /// document. (Written for whisper-server's per-segment output; harmless on Qwen3-ASR text.)
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
}
