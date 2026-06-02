import Testing
@testable import FridayMac

struct PostProcessServiceTests {
  private let service = PostProcessService()

  @Test
  func cleanupLightCollapsesWhitespaceAndAddsEnglishPunctuation() {
    let input = "  hello   world  "
    let output = service.cleanup(input, mode: .light)
    #expect(output == "hello world.")
  }

  @Test
  func cleanupLightAddsChinesePunctuation() {
    let input = "今天 开会 很 顺利"
    let output = service.cleanup(input, mode: .light)
    #expect(output == "今天 开会 很 顺利。")
  }

  @Test
  func cleanupLightPreservesTerminalPunctuation() {
    let input = "already done!"
    let output = service.cleanup(input, mode: .light)
    #expect(output == "already done!")
  }

  @Test
  func cleanupLightDoesNotAutoAppendMixedLanguagePunctuation() {
    let input = "今天 meeting 很顺利"
    let output = service.cleanup(input, mode: .light)
    #expect(output == "今天 meeting 很顺利")
  }

  @Test
  func cleanupNoneOnlyTrimsOuterWhitespace() {
    let input = "  hello   world  "
    let output = service.cleanup(input, mode: .none)
    #expect(output == "hello   world")
  }

  @Test
  func cleanupLightRemovesSpacesBeforePunctuation() {
    let input = "hello , world !"
    let output = service.cleanup(input, mode: .light)
    #expect(output == "hello, world!")
  }

  @Test
  func cleanupLightKeepsTripleEmphasis() {
    let input = "非常好 非常好 非常好"
    let output = service.cleanup(input, mode: .light)
    #expect(output == "非常好 非常好 非常好。")
  }

  @Test
  func cleanupLightCollapsesQuadruplePhraseNoise() {
    let input = "thank you thank you thank you thank you"
    let output = service.cleanup(input, mode: .light)
    #expect(output == "thank you.")
  }

  @Test
  func cleanupLightCollapsesFourRepeatedSentences() {
    let input = "Go now. Go now. Go now. Go now."
    let output = service.cleanup(input, mode: .light)
    #expect(output == "Go now.")
  }

  @Test
  func cleanupLightCollapsesThreeRepeatedSentences() {
    let input = "Go now. Go now. Go now."
    let output = service.cleanup(input, mode: .light)
    #expect(output == "Go now.")
  }

  @Test
  func cleanupLightDoesNotCollapseTwoRepeatedSentences() {
    let input = "Go now. Go now."
    let output = service.cleanup(input, mode: .light)
    #expect(output == "Go now. Go now.")
  }

  @Test
  func cleanupSmartCompactsChineseSpacingAndUsesChinesePunctuation() {
    let smart = TextCleanupMode(rawValue: "smart")
    #expect(smart != nil)

    let input = "今天 开会 很 顺利 , 明天 继续 跟进"
    let output = service.cleanup(input, mode: smart ?? .light)
    #expect(output == "今天开会很顺利，明天继续跟进")
  }

  @Test
  func cleanupSmartKeepsReadableChineseEnglishSpacing() {
    let smart = TextCleanupMode(rawValue: "smart")
    #expect(smart != nil)

    let input = "今天 meeting 效果 很 好 下次 follow up"
    let output = service.cleanup(input, mode: smart ?? .light)
    #expect(output == "今天 meeting 效果很好下次 follow up")
  }

  @Test
  func cleanupSmartDoesNotGuessQuestionMarkForChineseQuestionParticle() {
    // Friday must not infer a question mark from particles like 吗; the user
    // wants no terminal punctuation added at all in smart mode.
    let input = "你觉得这样可以吗"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "你觉得这样可以吗")
  }

  @Test
  func cleanupSmartDoesNotGuessQuestionMarkForChineseQuestionPhrase() {
    let input = "这个方案是不是更稳"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "这个方案是不是更稳")
  }

  @Test
  func cleanupSmartDoesNotAppendPeriodForChineseStatement() {
    let input = "今天先做到这里"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "今天先做到这里")
  }

  @Test
  func cleanupSmartFlattensWhisperLineBreaksIntoSingleLine() {
    // Whisper's own segment newlines should not split one passage into lines.
    let input = "这是第一行\n这是第二行\n这是第三行"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "这是第一行这是第二行这是第三行")
  }

  @Test
  func cleanupSmartTurnsDictationCommandsIntoLineBreaks() {
    let smart = TextCleanupMode(rawValue: "smart")
    #expect(smart != nil)

    let input = "第一点 今天 先 review 新段落 第二点 明天 follow up"
    let output = service.cleanup(input, mode: smart ?? .light)
    #expect(output == "第一点今天先 review\n\n第二点明天 follow up")
  }

  @Test
  func cleanupSmartNormalizesClaudeMisrecognitionsInMixedDictation() {
    let input = "今天用 cloud 和 claud 试一下然后让 clode 总结"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "今天用 Claude 和 Claude 试一下然后让 Claude 总结")
  }

  @Test
  func cleanupNormalizesClaudeVariantsInLightMode() {
    // Brand normalization must run in light mode too so users with a
    // non-smart cleanup setting still get cloud → Claude.
    let input = "ask cloud about this"
    let output = service.cleanup(input, mode: .light)
    #expect(output == "ask Claude about this.")
  }

  @Test
  func cleanupNormalizesClaudeVariantsInNoneMode() {
    // Even .none should fix Claude — it's user intent, not formatting.
    let input = "ask cloud about this"
    let output = service.cleanup(input, mode: .none)
    #expect(output == "ask Claude about this")
  }

  @Test
  func cleanupNormalizesClaudePluralAndLowercaseCanonical() {
    // "clouds" (plural) and lowercase "claude" both normalize to "Claude".
    let input = "用 clouds 和 claude 都可以"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "用 Claude 和 Claude 都可以")
  }

  @Test
  func cleanupNormalizesClaudeWithAdjacentPunctuation() {
    let input = "Cloud, can you review this?"
    let output = service.cleanup(input, mode: .light)
    #expect(output == "Claude, can you review this?")
  }

  @Test
  func cleanupNormalizesCodexVariantsInLightMode() {
    let input = "ask codec to refactor this"
    let output = service.cleanup(input, mode: .light)
    #expect(output == "ask Codex to refactor this.")
  }

  @Test
  func cleanupNormalizesCodexVariantsInNoneMode() {
    let input = "ask codec to refactor this"
    let output = service.cleanup(input, mode: .none)
    #expect(output == "ask Codex to refactor this")
  }

  @Test
  func cleanupNormalizesCodexCommonMisrecognitionsInMixedDictation() {
    // codec / codecs / cortex / code x / lowercase codex all → Codex.
    let input = "今天让 codec 和 codecs 还有 cortex 加上 code x 一起跑 codex"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "今天让 Codex 和 Codex 还有 Codex 加上 Codex 一起跑 Codex")
  }

  @Test
  func cleanupSmartNormalizesCommonMixedLanguageProductTerms() {
    let input = "今天用 open AI 和 chat GBT 写 system prompt 然后让 code X 生成 mac OS 的 Swift 示例"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "今天用 OpenAI 和 ChatGPT 写 system prompt 然后让 Codex 生成 macOS 的 Swift 示例")
  }

  @Test
  func cleanupSmartPreservesCommonEnglishPhrasesInMixedDictation() {
    let input = "帮我 review 这个 pull request 里面的 system prompt 和 voice input flow"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "帮我 review 这个 pull request 里面的 system prompt 和 voice input flow")
  }

  @Test
  func cleanupSmartPreservesEnglishCodePunctuationInMixedDictation() {
    let input = "这段代码是 function foo(a, b) 然后继续"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "这段代码是 function foo(a, b) 然后继续")
  }

  @Test
  func cleanupSmartPreservesURLPunctuationInMixedDictation() {
    let input = "打开 https://example.com/a?x=1 然后继续"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "打开 https://example.com/a?x=1 然后继续")
  }

  @Test
  func cleanupSmartAddsConservativeBreaksForLongUnpunctuatedChineseText() {
    let input = "我觉得今天这个版本比之前好一点但是整体输出还是太像一整段所以我们先用非常保守的方式补一点断句然后再看真实使用效果"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "我觉得今天这个版本比之前好一点，但是整体输出还是太像一整段，所以我们先用非常保守的方式补一点断句。然后再看真实使用效果")
  }
}
