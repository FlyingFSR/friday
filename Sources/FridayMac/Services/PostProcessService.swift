import Foundation

final class PostProcessService {
  func cleanup(_ rawText: String, mode: TextCleanupMode = .light) -> String {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return ""
    }

    // Always normalize Claude / Codex variants regardless of cleanup mode.
    // For this user the literal words "cloud" / "codec" are almost never
    // the intended dictation; whisper frequently mis-recognizes "Claude"
    // and "Codex" as those words. Running this in every mode (including
    // .none) guarantees the fix even if cleanup is turned off, and also
    // fixes lowercase "claude" / "codex" → canonical casing.
    var normalized = normalizeClaudeBrand(in: trimmed)
    normalized = normalizeCodexBrand(in: normalized)

    switch mode {
    case .none:
      return normalized
    case .light:
      return cleanupLight(normalized)
    case .smart:
      return cleanupSmart(normalized)
    }
  }

  /// Map common whisper mis-recognitions of "Claude" to the canonical form.
  /// Covers singular, plural, and lowercase canonical spelling. Intentionally
  /// aggressive: legitimate "cloud" mentions are rare for this user and the
  /// reverse error (Claude → cloud) is far more painful.
  private func normalizeClaudeBrand(in text: String) -> String {
    // Longer variants first so "clouds" isn't partially matched as "cloud".
    let pattern = "\\b(?:clouds|cloud|claude|claud|clode|clored|clord)\\b"
    return text.replacingOccurrences(
      of: pattern,
      with: "Claude",
      options: [.regularExpression, .caseInsensitive]
    )
  }

  /// Map common whisper mis-recognitions of "Codex" to the canonical form.
  /// Covers "code x" / "code-x" spacing, plural/possessive forms, and the
  /// frequent "codec" / "codecs" / "cortex" / "cordex" mis-hears.
  /// Intentionally aggressive — the user has confirmed they mean "Codex"
  /// whenever they say anything that sounds like it.
  private func normalizeCodexBrand(in text: String) -> String {
    // Longer variants first so e.g. "codecs" isn't partially matched as "codec".
    let pattern = "\\b(?:codecs|codec|codexes|codex|cortex|cordex|coatex|code[\\s-]*x)\\b"
    return text.replacingOccurrences(
      of: pattern,
      with: "Codex",
      options: [.regularExpression, .caseInsensitive]
    )
  }

  private func cleanupLight(_ trimmed: String) -> String {
    var text = trimmed
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: "\\s+([,\\.!\\?;:，。！？；：])", with: "$1", options: .regularExpression)
    text = collapseRepeatedPhrases(text)
    text = collapseRepeatedSentences(text)

    guard !text.isEmpty else {
      return text
    }

    if needsTerminalPunctuation(text) {
      switch LanguageDetector.detect(in: text) {
      case .zh:
        text += preferredTerminalPunctuation(for: text)
      case .en:
        text += "."
      case .mixed, .unknown:
        break
      }
    }
    return text
  }

  private func cleanupSmart(_ trimmed: String) -> String {
    var text = replaceDictationCommands(in: trimmed)
    text = normalizePersonalTerms(in: text)
    text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
    text = text.replacingOccurrences(of: "\\s+([,\\.!\\?;:，。！？；：])", with: "$1", options: .regularExpression)

    text = collapseRepeatedPhrases(text)
    text = collapseRepeatedSentences(text)
    text = normalizePunctuationForSmartMode(text)
    text = removeUnnaturalCJKSpaces(text)
    text = addConservativeChineseBreaksIfNeeded(text)
    text = text
      .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "\\n[ \\t]+", with: "\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty else {
      return text
    }

    if needsTerminalPunctuation(text) {
      text += preferredTerminalPunctuation(for: text)
    }
    return text
  }

  private func replaceDictationCommands(in text: String) -> String {
    var output = text
    let replacements = [
      ("新段落", "\n\n"),
      ("另起一段", "\n\n"),
      ("换行", "\n"),
      ("下一行", "\n"),
      ("冒号", "："),
      ("逗号", "，"),
      ("句号", "。")
    ]

    for (spoken, symbol) in replacements {
      output = output.replacingOccurrences(
        of: "\\s*\(NSRegularExpression.escapedPattern(for: spoken))\\s*",
        with: symbol,
        options: .regularExpression
      )
    }
    return output
  }

  private func normalizePersonalTerms(in text: String) -> String {
    // Claude and Codex variants are handled unconditionally in
    // `cleanup(_:mode:)` via `normalizeClaudeBrand` / `normalizeCodexBrand`;
    // keep this list focused on smart-mode-only terms.
    var output = text
    let replacements = [
      ("\\bopen\\s*ai\\b", "OpenAI"),
      ("\\bchat\\s*(?:gpt|gbt)\\b", "ChatGPT"),
      ("\\bmac\\s*os\\b", "macOS"),
      ("\\bswift\\b", "Swift")
    ]
    for (pattern, replacement) in replacements {
      output = output.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: [.regularExpression, .caseInsensitive]
      )
    }
    return output
  }

  private func normalizePunctuationForSmartMode(_ text: String) -> String {
    guard containsCJK(text) else {
      return text
    }

    let characters = Array(text)
    var output = ""
    let replacements = [
      Character(","): Character("，"),
      Character(";"): Character("；"),
      Character(":"): Character("："),
      Character("?"): Character("？"),
      Character("!"): Character("！")
    ]

    for index in characters.indices {
      let character = characters[index]
      if let replacement = replacements[character],
         shouldConvertWesternPunctuation(at: index, in: characters) {
        output.append(replacement)
      } else {
        output.append(character)
      }
    }
    return output
  }

  private func shouldConvertWesternPunctuation(at index: Int, in characters: [Character]) -> Bool {
    let previous = nearestNonSpace(before: index, in: characters)
    let next = nearestNonSpace(after: index, in: characters)

    if previous.map(isLatinOrDigit) == true || next.map(isLatinOrDigit) == true {
      return false
    }
    return previous.map(isCJK) == true || next.map(isCJK) == true
  }

  private func removeUnnaturalCJKSpaces(_ text: String) -> String {
    let characters = Array(text)
    var output = ""

    for index in characters.indices {
      let character = characters[index]
      if character == " " {
        let previous = nearestNonSpace(before: index, in: characters)
        let next = nearestNonSpace(after: index, in: characters)
        if let previous, let next, shouldRemoveSpaceBetween(previous, next) {
          continue
        }
      }
      output.append(character)
    }

    return output
  }

  private func addConservativeChineseBreaksIfNeeded(_ text: String) -> String {
    guard containsCJK(text),
          !containsLatinLetter(text),
          text.count >= 40,
          !containsReadablePunctuation(text) else {
      return text
    }

    var output = text
    let commaMarkers = ["但是", "不过", "所以", "因为", "如果"]
    let sentenceMarkers = ["然后", "另外", "接下来", "最后"]

    for marker in commaMarkers {
      output = insertBreak(before: marker, punctuation: "，", in: output, minimumLeadingCharacters: 8)
    }
    for marker in sentenceMarkers {
      output = insertBreak(before: marker, punctuation: "。", in: output, minimumLeadingCharacters: 18)
    }
    return output
  }

  private func containsReadablePunctuation(_ text: String) -> Bool {
    text.contains { character in
      ",，;；:：.!?。！？\n".contains(character)
    }
  }

  private func containsLatinLetter(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }
  }

  private func insertBreak(
    before marker: String,
    punctuation: Character,
    in text: String,
    minimumLeadingCharacters: Int
  ) -> String {
    var output = ""
    var searchStart = text.startIndex

    while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
      let leadingDistance = text.distance(from: text.startIndex, to: range.lowerBound)
      output.append(contentsOf: text[searchStart..<range.lowerBound])

      if leadingDistance >= minimumLeadingCharacters,
         output.last.map({ !isBreakPunctuation($0) }) ?? false {
        output.append(punctuation)
      }

      output.append(contentsOf: text[range])
      searchStart = range.upperBound
    }

    output.append(contentsOf: text[searchStart..<text.endIndex])
    return output
  }

  private func isBreakPunctuation(_ character: Character) -> Bool {
    ",，;；:：.!?。！？\n".contains(character)
  }

  private func nearestNonSpace(before index: Int, in characters: [Character]) -> Character? {
    guard index > characters.startIndex else {
      return nil
    }
    var cursor = characters.index(before: index)
    while true {
      let character = characters[cursor]
      if character != " " {
        return character
      }
      if cursor == characters.startIndex {
        return nil
      }
      cursor = characters.index(before: cursor)
    }
  }

  private func nearestNonSpace(after index: Int, in characters: [Character]) -> Character? {
    var cursor = characters.index(after: index)
    while cursor < characters.endIndex {
      let character = characters[cursor]
      if character != " " {
        return character
      }
      cursor = characters.index(after: cursor)
    }
    return nil
  }

  private func shouldRemoveSpaceBetween(_ left: Character, _ right: Character) -> Bool {
    if isCJK(left), isCJK(right) {
      return true
    }
    if isCJK(left), isChinesePunctuation(right) {
      return true
    }
    if isChinesePunctuation(left), isCJK(right) {
      return true
    }
    return false
  }

  private func containsCJK(_ text: String) -> Bool {
    text.unicodeScalars.contains(where: isCJK)
  }

  private func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains(where: isCJK)
  }

  private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x4E00...0x9FFF, 0x3400...0x4DBF:
      return true
    default:
      return false
    }
  }

  private func isChinesePunctuation(_ character: Character) -> Bool {
    "，。！？；：、".contains(character)
  }

  private func isLatinOrDigit(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      (48...57).contains(scalar.value) ||
        (65...90).contains(scalar.value) ||
        (97...122).contains(scalar.value)
    }
  }

  private func collapseRepeatedPhrases(_ text: String) -> String {
    guard let regex = try? NSRegularExpression(
      pattern: "(?i)\\b((?:\\S+\\s+){0,5}\\S+)(?:\\s+\\1){3,}\\b"
    ) else {
      return text
    }
    let collapsed = regex.stringByReplacingMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text),
      withTemplate: "$1"
    )
    return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func collapseRepeatedSentences(_ text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: "[^.!?。！？]+[.!?。！？]?") else {
      return text
    }

    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    guard !matches.isEmpty else {
      return text
    }

    let units: [(raw: String, normalized: String)] = matches.compactMap { match in
      guard let range = Range(match.range, in: text) else {
        return nil
      }
      let raw = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !raw.isEmpty else {
        return nil
      }
      let normalized = raw
        .lowercased()
        .replacingOccurrences(of: "[.!?。！？]+$", with: "", options: .regularExpression)
      return (raw, normalized)
    }

    guard !units.isEmpty else {
      return text
    }

    let minConsecutiveRepeats = 3
    var output: [String] = []
    var index = 0
    var didCollapse = false

    while index < units.count {
      var next = index + 1
      while next < units.count && units[next].normalized == units[index].normalized {
        next += 1
      }

      let repeatCount = next - index
      if repeatCount >= minConsecutiveRepeats {
        output.append(units[index].raw)
        didCollapse = true
      } else {
        output.append(contentsOf: units[index..<next].map(\.raw))
      }
      index = next
    }

    guard didCollapse else {
      return text
    }
    return output.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func needsTerminalPunctuation(_ text: String) -> Bool {
    guard let last = text.last else {
      return false
    }

    let punctuation = ".!?。！？"
    return !punctuation.contains(last)
  }

  private func preferredTerminalPunctuation(for text: String) -> String {
    guard containsCJK(text) else {
      return "."
    }
    return looksLikeChineseQuestion(text) ? "？" : "。"
  }

  private func looksLikeChineseQuestion(_ text: String) -> Bool {
    let normalized = text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    let questionSuffixes = ["吗", "么", "呢"]
    if questionSuffixes.contains(where: normalized.hasSuffix) {
      return true
    }

    let questionPhrases = [
      "是不是", "有没有", "能不能", "可不可以", "要不要", "会不会", "该不该",
      "行不行", "是否"
    ]
    if questionPhrases.contains(where: normalized.contains) {
      return true
    }

    let tailLength = min(12, normalized.count)
    let tailStart = normalized.index(normalized.endIndex, offsetBy: -tailLength)
    let tail = String(normalized[tailStart...])
    let tailQuestionWords = [
      "为什么", "怎么", "怎样", "如何", "什么", "哪里", "哪儿", "哪个",
      "哪一个", "谁", "多少", "几"
    ]
    return tailQuestionWords.contains(where: tail.contains)
  }
}
