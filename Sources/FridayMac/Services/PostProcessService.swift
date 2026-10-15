import Foundation

final class PostProcessService {
  func cleanup(_ rawText: String, mode: TextCleanupMode = .smart) -> String {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return ""
    }

    // Always normalize Claude / Codex / Fable / Sol variants regardless of cleanup mode.
    // Whisper frequently mis-recognizes Claude / Codex, and the user has also
    // confirmed that Fable / Sol should win over their ordinary-word variants.
    // Running these in every mode (including .none) guarantees the intended
    // names and canonical casing even if cleanup is turned off.
    var normalized = normalizeClaudeBrand(in: trimmed)
    normalized = normalizeCodexBrand(in: normalized)
    normalized = normalizeFableBrand(in: normalized)
    normalized = normalizeSolBrand(in: normalized)
    normalized = normalizeWhisperBrand(in: normalized)
    normalized = normalizeCommonProductTerms(in: normalized)
    normalized = normalizePullRequestPhrase(in: normalized)
    normalized = normalizeChineseBookingHomophone(in: normalized)

    switch mode {
    case .none:
      return normalized
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
    // Use lookarounds instead of \b: in ICU regex CJK counts as a word
    // character, so \b fails to match when the brand word is glued directly to
    // Chinese (e.g. "用cloud写"). Latin/digit lookarounds still avoid matching
    // inside longer English words like "icloud" / "clouded".
    let pattern = "(?<![A-Za-z0-9])(?:clouds|cloud|claude|claud|clode|clored|clord)(?![A-Za-z0-9])"
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
    let pattern = "(?<![A-Za-z0-9])(?:codecs|codec|codexes|codex|cortex|cordex|coatex|code[\\s-]*x)(?![A-Za-z0-9])"
    return text.replacingOccurrences(
      of: pattern,
      with: "Codex",
      options: [.regularExpression, .caseInsensitive]
    )
  }

  /// Map the user's confirmed Fable variants to the canonical form.
  /// Intentionally aggressive: the user has confirmed they only say the Fable
  /// name itself, so replacing the ordinary English word "fable" is accepted.
  private func normalizeFableBrand(in text: String) -> String {
    // Longer variants first; Latin/digit lookarounds avoid matching fragments
    // inside longer English words while still supporting text glued to CJK.
    let pattern = "(?<![A-Za-z0-9])(?:fables|faible|fabel|fable)(?![A-Za-z0-9])"
    return text.replacingOccurrences(
      of: pattern,
      with: "Fable",
      options: [.regularExpression, .caseInsensitive]
    )
  }

  /// Map the user's confirmed Sol variants to the canonical form.
  /// Intentionally aggressive: the user has confirmed they only say the Sol
  /// name itself, so replacing ordinary "soul" / "sole" words is accepted.
  private func normalizeSolBrand(in text: String) -> String {
    // Longer plural variants first; lookarounds keep embedded fragments in
    // words such as "console", "solution", and "parasol" untouched.
    let pattern = "(?<![A-Za-z0-9])(?:souls|soles|soul|sole|sol)(?![A-Za-z0-9])"
    return text.replacingOccurrences(
      of: pattern,
      with: "Sol",
      options: [.regularExpression, .caseInsensitive]
    )
  }

  /// Map common whisper mis-recognitions of "Whisper" itself to the canonical form.
  /// Intentionally aggressive: the user only ever means the speech-recognition
  /// engine, so replacing the ordinary English word "whispers" is accepted.
  private func normalizeWhisperBrand(in text: String) -> String {
    // Longer variants first so "whispers" isn't partially matched as "whisper".
    // The ".cpp" / "-" lookaheads keep the lowercase proper nouns this app itself
    // primes (whisper.cpp, whisper-cli) intact, while a sentence-final
    // "whisper." still normalizes.
    let pattern = "(?<![A-Za-z0-9])(?:whispers|wispers|whisper|wisper)(?![A-Za-z0-9])(?!\\.cpp)(?!-)"
    return text.replacingOccurrences(
      of: pattern,
      with: "Whisper",
      options: [.regularExpression, .caseInsensitive]
    )
  }

  /// Canonical casing for the product names the user dictates constantly.
  /// These were smart-mode-only, but the mis-recognitions (open AI / chat GBT /
  /// MAC OS) show up in every mode, so they run unconditionally like the brand
  /// rules above. "Swift" stays smart-mode-only in `normalizePersonalTerms`:
  /// it is an ordinary English word and too risky to capitalize everywhere.
  private func normalizeCommonProductTerms(in text: String) -> String {
    var output = text
    let replacements = [
      ("(?<![A-Za-z0-9])open\\s*ai(?![A-Za-z0-9])", "OpenAI"),
      ("(?<![A-Za-z0-9])chat\\s*(?:gpt|gbt)(?![A-Za-z0-9])", "ChatGPT"),
      ("(?<![A-Za-z0-9])mac\\s*os(?![A-Za-z0-9])", "macOS"),
      // Mainstream AI companies / models. Only names that are not ordinary
      // English words live here; ordinary-word names (Opus, Cursor …) are
      // smart-mode-only in `normalizePersonalTerms`. "gbt" is the same mis-hear
      // seen in "chat GBT".
      // "deep sync" / "deepseq" / "qn" / 签问 are observed mis-hears from the user's
      // dictation (seeq / seak / sik are close spellings of the same sound);
      // 签问 skips 求签问卜 / 抽签问… where it is the ordinary phrase.
      // From the 2026-10 read-aloud list: kemi / qwin / hiku / grock / lama, plus
      // 同意千问 and 质朴 GLM; round two added deepsec / qoan / haicoo / 混源. 同意 and 质朴 are ordinary words, so those two are only
      // rewritten right in front of 千问 / GLM; "lama" keeps "Dalai Lama".
      ("(?<![A-Za-z0-9])deep[\\s-]*(?:seek|seeq|seak|seq|sec|sik|sync)(?![A-Za-z0-9])", "DeepSeek"),
      ("(?<![A-Za-z0-9])(?:kimi|kimmy|kemi)(?![A-Za-z0-9])", "Kimi"),
      ("(?<![A-Za-z0-9])(?:q[\\s-]*w[ei]n|qn|qoan)(?![A-Za-z0-9])", "Qwen"),
      ("(?<![求抽])签问", "千问"),
      ("[通同][义意]千问", "通义千问"),
      // Qwen3-ASR writes 通义千问 as 通一千万 (2 of 3 recordings, docs/qwen3-asr-eval-2026-10.md).
      // 通一千万 is otherwise only the tail of 流通/开通/打通… 一千万, which stays.
      ("(?<![流开打交联互畅贯沟融普变])通[一义意]千万", "通义千问"),
      ("混源", "混元"),
      // Perplexity itself is smart-mode-only below; these two mis-hears are not words.
      ("(?<![A-Za-z0-9])(?:pervlexity|pervoluxity)(?![A-Za-z0-9])", "Perplexity"),
      ("质朴(?=\\s*的?\\s*glm(?![A-Za-z0-9]))", "智谱"),
      ("(?<![A-Za-z0-9])(?:hiku|hai[\\s-]*coo)(?![A-Za-z0-9])", "Haiku"),
      ("(?<![A-Za-z0-9])gemini(?![A-Za-z0-9])", "Gemini"),
      ("(?<![A-Za-z0-9])anthropic(?![A-Za-z0-9])", "Anthropic"),
      ("(?<![A-Za-z0-9])gro(?:ck|k)(?![A-Za-z0-9])", "Grok"),
      ("(?<![A-Za-z0-9])(?:llama|(?<!dalai\\s)lama)(?![A-Za-z0-9])", "Llama"),
      ("(?<![A-Za-z0-9])mistral(?![A-Za-z0-9])", "Mistral"),
      ("(?<![A-Za-z0-9])mini[\\s-]*max(?![A-Za-z0-9])", "MiniMax"),
      ("(?<![A-Za-z0-9])mid[\\s-]*journey(?![A-Za-z0-9])", "Midjourney"),
      ("(?<![A-Za-z0-9])glm(?![A-Za-z0-9])", "GLM"),
      // "GPT5" / "gpt 4o" → "GPT-5" / "GPT-4o", the official hyphenated spelling.
      ("(?<![A-Za-z0-9])(?:gpt|gbt)[\\s-]*(?=\\d)", "GPT-"),
      // Qwen3-ASR writes the version as a Chinese numeral ("GPT五"). Not before a measure
      // word, where 四/五 is a count ("GPT 四个版本").
      ("(?<![A-Za-z0-9])(?:gpt|gbt)[\\s-]*四(?![个种次年位款家版名条只岁点分])", "GPT-4"),
      ("(?<![A-Za-z0-9])(?:gpt|gbt)[\\s-]*五(?![个种次年位款家版名条只岁点分])", "GPT-5"),
      ("(?<![A-Za-z0-9])(?:gpt|gbt)(?![A-Za-z0-9])", "GPT")
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

  /// Fix the observed "pull request" → "pool request" mis-hear. Deliberately
  /// contextual: only the word immediately before "request" / "requests" is
  /// rewritten, so a bare "pool" keeps its ordinary meaning.
  private func normalizePullRequestPhrase(in text: String) -> String {
    // Case-sensitive pass first so a sentence-initial "Pool request" keeps its
    // capital; the case-insensitive pass then covers every other spelling.
    var output = text.replacingOccurrences(
      of: "(?<![A-Za-z0-9])Pool(?=\\s+[Rr]equests?(?![A-Za-z0-9]))",
      with: "Pull",
      options: .regularExpression
    )
    output = output.replacingOccurrences(
      of: "(?<![A-Za-z0-9])pool(?=\\s+requests?(?![A-Za-z0-9]))",
      with: "pull",
      options: [.regularExpression, .caseInsensitive]
    )
    return output
  }

  /// Fix the 订 / 定 homophone in booking contexts (订机票 heard as 定机票).
  /// Deliberately narrow on both sides: the character must be followed by one of
  /// a few booking objects, and must not be the tail of a common compound
  /// (一定 / 决定 / 确定 / 预定 …), which the negative lookbehind list guards.
  private func normalizeChineseBookingHomophone(in text: String) -> String {
    // "不" covers 说不定 / 指不定 / 保不定; the rest are ordinary 定-compounds.
    let compoundPrefixes = "不一决确规肯固稳设指约必否认鉴注制限特既暂裁判核锁选敲商断预假安淡搞内议拟平镇咬界划测审评法原铁笃绑"
    let bookingObjects = "机票|位子|酒店|餐厅|外卖|车票|门票|房间"
    // The optional 了 and the optional measure word keep the spoken forms working
    // ("定个位子" / "提前定了个位子" / "定了一张车票") without widening the booking-object
    // list itself. Only this fixed middle is allowed, so 定 still has to sit right
    // in front of the object.
    let bookingMiddle = "了?(?:一?[个张间])?"
    let pattern = "(?<![\(compoundPrefixes)])定(\(bookingMiddle))(?=\(bookingObjects))"
    return text.replacingOccurrences(
      of: pattern,
      with: "订$1",
      options: .regularExpression
    )
  }

  private func cleanupSmart(_ trimmed: String) -> String {
    // Whisper inserts line breaks at its own segment boundaries, which splits
    // a single spoken passage across several lines. Flatten those raw newlines
    // to spaces first; the explicit voice commands (新段落 / 换行) handled below
    // reintroduce only the breaks the user actually asked for.
    // A mark the user dictated out loud ("句号") is an explicit instruction, not
    // a guess about intent, so it has to survive the terminal strip at the end.
    // Record that before the commands are converted — afterwards the mark is
    // indistinguishable from one the model produced on its own.
    let endsWithDictatedPunctuation = endsWithSpokenPunctuationCommand(trimmed)

    var text = trimmed.replacingOccurrences(
      of: "\\s*\\n\\s*",
      with: " ",
      options: .regularExpression
    )
    text = replaceDictationCommands(in: text)
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
    // Intentionally no terminal punctuation in smart mode: the user does not
    // want Friday to guess sentence endings for dictated speech (especially
    // auto-inserting a question mark from heuristics like 吗 / 是不是).
    let normalized = text
      .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "\\n[ \\t]+", with: "\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return stripTerminalPunctuation(
      normalized,
      keepingDictatedFinalMark: endsWithDictatedPunctuation
    )
  }

  /// True when the utterance ends with a spoken punctuation command, i.e. the
  /// final mark of the cleaned text was explicitly asked for. Mirrors the
  /// punctuation entries of the command table in `replaceDictationCommands`;
  /// 换行 / 新段落 are absent because they produce breaks, not marks.
  private func endsWithSpokenPunctuationCommand(_ text: String) -> Bool {
    let punctuationCommands = ["句号", "逗号", "冒号"]
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return punctuationCommands.contains(where: trimmed.hasSuffix)
  }

  /// Drop the sentence-terminal mark the utterance ends with, whoever produced
  /// it. Whisper now emits its own punctuation, but it cannot hear whether the
  /// user meant 。 or ？ — the mark is always a guess about intent, and the user's
  /// explicit rule (2026-08-29) is that no mark beats a guessed one. Internal
  /// punctuation is untouched: only the very end of the text is trimmed.
  private func stripTerminalPunctuation(
    _ text: String,
    keepingDictatedFinalMark: Bool = false
  ) -> String {
    if keepingDictatedFinalMark, let dictatedMark = text.last {
      // The last character came from a spoken command, so keep it and apply the
      // normal strip to everything in front of it. "……结束了。句号" therefore ends
      // with a single 。 rather than a doubled one.
      return stripTerminalPunctuation(String(text.dropLast())) + String(dictatedMark)
    }

    let terminalMarks: Set<Character> = ["。", "．", ".", "？", "?", "！", "!"]
    // A run of three or more is a deliberate ellipsis ("..." / "。。。"), not a
    // sentence ending, so it stays. 中文省略号 …… never matches at all.
    let trailingRun = text.reversed().prefix(while: { terminalMarks.contains($0) }).count
    guard (1...2).contains(trailingRun) else {
      return text
    }
    return String(text.dropLast(trailingRun))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func replaceDictationCommands(in text: String) -> String {
    let commands = [
      ("新段落", "\n\n"),
      ("另起一段", "\n\n"),
      ("换行", "\n"),
      ("下一行", "\n"),
      ("冒号", "："),
      ("逗号", "，"),
      ("句号", "。")
    ]

    // These deterministic phrases are high-confidence literal uses of text
    // that otherwise contains a dictation command. Keep this table narrow:
    // ambiguous text defaults to command behavior so the primary voice-input
    // flow remains reliable.
    let protectedLiteralPhrases = [
      "换行业",
      "换行符",
      "换行键",
      "换行之后",
      "下一行动",
      "句号召",
      "句号后面",
      "逗号表达式",
      "新段落之前",
      "另起一段之前"
    ]
    let protectedRanges = protectedLiteralPhrases.flatMap { literalRanges(of: $0, in: text) }

    let commandPattern = commands
      .map { NSRegularExpression.escapedPattern(for: $0.0) }
      .joined(separator: "|")
    guard let regex = try? NSRegularExpression(
      pattern: "\\s*(\(commandPattern))\\s*"
    ) else {
      return text
    }

    let matches = regex.matches(
      in: text,
      range: NSRange(text.startIndex..<text.endIndex, in: text)
    )
    var output = ""
    var cursor = text.startIndex

    for match in matches {
      guard let fullRange = Range(match.range, in: text),
            let commandRange = Range(match.range(at: 1), in: text) else {
        continue
      }

      output += text[cursor..<fullRange.lowerBound]
      if protectedRanges.contains(where: { $0.overlaps(commandRange) }) {
        output += text[fullRange]
      } else {
        let spoken = String(text[commandRange])
        output += commands.first(where: { $0.0 == spoken })?.1 ?? spoken
      }
      cursor = fullRange.upperBound
    }

    output += text[cursor...]
    return output
  }

  private func literalRanges(of literal: String, in text: String) -> [Range<String.Index>] {
    var ranges: [Range<String.Index>] = []
    var searchStart = text.startIndex

    while searchStart < text.endIndex,
          let range = text.range(
            of: literal,
            range: searchStart..<text.endIndex
          ) {
      ranges.append(range)
      searchStart = range.upperBound
    }
    return ranges
  }

  private func normalizePersonalTerms(in text: String) -> String {
    // Brand variants and the always-on product terms (OpenAI / ChatGPT / macOS)
    // are handled unconditionally in `cleanup(_:mode:)`; keep this list focused
    // on smart-mode-only terms.
    var output = text
    let replacements = [
      ("(?<![A-Za-z0-9])swift(?![A-Za-z0-9])", "Swift"),
      // AI product / model names that double as ordinary English words.
      ("(?<![A-Za-z0-9])opus(?![A-Za-z0-9])", "Opus"),
      ("(?<![A-Za-z0-9])sonnet(?![A-Za-z0-9])", "Sonnet"),
      ("(?<![A-Za-z0-9])haiku(?![A-Za-z0-9])", "Haiku"),
      ("(?<![A-Za-z0-9])cursor(?![A-Za-z0-9])", "Cursor"),
      ("(?<![A-Za-z0-9])co-?pilot(?![A-Za-z0-9])", "Copilot"),
      ("(?<![A-Za-z0-9])perplexity(?![A-Za-z0-9])", "Perplexity")
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
    CJKScript.containsCJK(text)
  }

  private func isCJK(_ character: Character) -> Bool {
    CJKScript.isCJK(character)
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
    // The pattern matches whitespace-separated phrases, so spaceless text can never produce a hit —
    // but the engine still tries every start/length pair on it, which is quadratic on a long Chinese
    // paragraph (and joinTranscriptSegments now deliberately glues those into one spaceless run:
    // ~28ms before joining vs ~263ms after, at 2000 characters). Chinese repeats are
    // collapseRepeatedSentences' job.
    guard text.contains(where: \.isWhitespace) else {
      return text
    }
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

}
