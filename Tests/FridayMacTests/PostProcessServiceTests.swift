import Testing
@testable import FridayMac

struct PostProcessServiceTests {
  private let service = PostProcessService()

  @Test
  func cleanupNormalizesBrandWhenGluedToChinese() {
    #expect(service.cleanup("今天我用cloud写React组件", mode: .smart).contains("Claude"))
    #expect(service.cleanup("我让codec跑一下", mode: .smart).contains("Codex"))
    // Must not corrupt longer English words that merely contain the token.
    #expect(service.cleanup("download to icloud", mode: .smart).contains("icloud"))
  }

  @Test
  func cleanupNormalizesEverySpecifiedFableVariant() {
    let input = "fables fable fabel faible FABLE FaIbLe"
    let output = service.cleanup(input, mode: .none)
    #expect(output == "Fable Fable Fable Fable Fable Fable")
  }

  @Test
  func cleanupNormalizesEverySpecifiedSolVariant() {
    let input = "souls soul soles sole sol SOL SoUl"
    let output = service.cleanup(input, mode: .none)
    #expect(output == "Sol Sol Sol Sol Sol Sol Sol")
  }

  @Test
  func cleanupNormalizesFableAndSolWhenGluedToChinese() {
    #expect(service.cleanup("用fable写", mode: .smart) == "用Fable写")
    #expect(service.cleanup("用sol写", mode: .smart) == "用Sol写")
  }

  @Test
  func cleanupDoesNotNormalizeFableOrSolFragmentsInsideLongerWords() {
    let input = "console solution fabulous parasol"
    #expect(service.cleanup(input, mode: .none) == input)
  }

  @Test
  func cleanupNormalizesPersonalNamesInEveryModeButLeavesRelayUntouched() {
    let input = "fable soul relay Relay"
    #expect(service.cleanup(input, mode: .none) == "Fable Sol relay Relay")
    #expect(service.cleanup(input, mode: .smart) == "Fable Sol relay Relay")
  }

  @Test
  func cleanupNoneOnlyTrimsOuterWhitespace() {
    let input = "  hello   world  "
    let output = service.cleanup(input, mode: .none)
    #expect(output == "hello   world")
  }

  @Test
  func cleanupSmartKeepsTripleEmphasis() {
    // The phrase collapser needs four occurrences; three stay as emphasis.
    let input = "非常好 非常好 非常好"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "非常好非常好非常好")
  }

  @Test
  func cleanupSmartCollapsesQuadruplePhraseNoise() {
    let input = "thank you thank you thank you thank you"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "thank you")
  }

  @Test
  func cleanupLeavesLongSpacelessChineseTextUntouchedByThePhraseCollapser() {
    // The phrase collapser only ever matches whitespace-separated phrases, so a joined
    // Chinese paragraph must pass through unchanged (and without paying for the search).
    let input = String(repeating: "今天下午我们出门的时候天还好好的结果刚走到地铁站就下起了大雨", count: 40)
    #expect(service.cleanup(input, mode: .smart) == input)
    #expect(service.cleanup(input, mode: .none) == input)
  }

  @Test
  func cleanupStillCollapsesRepeatedEnglishPhrasesAfterTheSpacelessGuard() {
    let input = "thank you very much thank you very much thank you very much thank you very much"
    #expect(service.cleanup(input, mode: .smart) == "thank you very much")
  }

  @Test
  func cleanupSmartCollapsesFourRepeatedSentences() {
    let input = "Go now. Go now. Go now. Go now."
    let output = service.cleanup(input, mode: .smart)
    // The final period is dropped by the terminal-punctuation rule.
    #expect(output == "Go now")
  }

  @Test
  func cleanupSmartCollapsesThreeRepeatedSentences() {
    let input = "Go now. Go now. Go now."
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "Go now")
  }

  @Test
  func cleanupSmartDoesNotCollapseTwoRepeatedSentences() {
    let input = "Go now. Go now."
    let output = service.cleanup(input, mode: .smart)
    // Only the trailing period goes; the sentence break inside stays.
    #expect(output == "Go now. Go now")
  }

  @Test
  func cleanupSmartCompactsChineseSpacingAndUsesChinesePunctuation() {
    let smart = TextCleanupMode(rawValue: "smart")
    #expect(smart != nil)

    let input = "今天 开会 很 顺利 , 明天 继续 跟进"
    let output = service.cleanup(input, mode: smart ?? .smart)
    #expect(output == "今天开会很顺利，明天继续跟进")
  }

  @Test
  func cleanupSmartKeepsReadableChineseEnglishSpacing() {
    let smart = TextCleanupMode(rawValue: "smart")
    #expect(smart != nil)

    let input = "今天 meeting 效果 很 好 下次 follow up"
    let output = service.cleanup(input, mode: smart ?? .smart)
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
    let output = service.cleanup(input, mode: smart ?? .smart)
    #expect(output == "第一点今天先 review\n\n第二点明天 follow up")
  }

  @Test
  func cleanupSmartReplacesEveryDictationCommandWhenGluedToChineseText() {
    let cases = [
      ("甲新段落乙", "甲\n\n乙"),
      ("甲另起一段乙", "甲\n\n乙"),
      ("甲换行乙", "甲\n乙"),
      ("甲下一行乙", "甲\n乙"),
      ("甲冒号乙", "甲：乙"),
      ("甲逗号乙", "甲，乙"),
      ("甲句号乙", "甲。乙")
    ]

    for (input, expected) in cases {
      #expect(service.cleanup(input, mode: .smart) == expected)
    }
  }

  @Test
  func cleanupSmartReplacesEverySpacedDictationCommandAndConsumesSurroundingSpaces() {
    let cases = [
      ("甲   新段落   乙", "甲\n\n乙"),
      ("甲   另起一段   乙", "甲\n\n乙"),
      ("甲   换行   乙", "甲\n乙"),
      ("甲   下一行   乙", "甲\n乙"),
      ("甲   冒号   乙", "甲：乙"),
      ("甲   逗号   乙", "甲，乙"),
      ("甲   句号   乙", "甲。乙")
    ]

    for (input, expected) in cases {
      #expect(service.cleanup(input, mode: .smart) == expected)
    }
  }

  @Test
  func cleanupSmartPreservesConfirmedDictationCommandFalsePositives() {
    let cases = [
      "我打算换行业了",
      "一句号召力很强的口号",
      "下一行动计划",
      "新段落之前"
    ]

    for input in cases {
      #expect(service.cleanup(input, mode: .smart) == input)
    }
  }

  @Test
  func cleanupSmartPreservesHighConfidenceLiteralCommandPhrases() {
    let cases = [
      "换行符",
      "换行键",
      "换行之后",
      "逗号表达式",
      "句号后面",
      "新段落之前",
      "另起一段之前"
    ]

    for input in cases {
      #expect(service.cleanup(input, mode: .smart) == input)
    }
  }

  @Test
  func cleanupSmartPreservesLiteralPhraseWithoutSwallowingRealCommandInSameSentence() {
    let input = "请解释换行符换行继续"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "请解释换行符\n继续")
  }

  @Test
  func cleanupSmartHandlesCommandsAtBoundariesAndConsecutiveCommands() {
    #expect(service.cleanup("换行正文", mode: .smart) == "正文")
    #expect(service.cleanup("正文换行", mode: .smart) == "正文")
    #expect(service.cleanup("甲冒号句号乙", mode: .smart) == "甲：。乙")
  }

  @Test
  func cleanupNoneDoesNotReplaceDictationCommands() {
    let input = "第一点换行第二点"
    #expect(service.cleanup(input, mode: .none) == input)
  }

  @Test
  func cleanupSmartNormalizesClaudeMisrecognitionsInMixedDictation() {
    let input = "今天用 cloud 和 claud 试一下然后让 clode 总结"
    let output = service.cleanup(input, mode: .smart)
    #expect(output == "今天用 Claude 和 Claude 试一下然后让 Claude 总结")
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
    let output = service.cleanup(input, mode: .none)
    #expect(output == "Claude, can you review this?")
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

  @Test
  func cleanupNormalizesProductTermsInNoneMode() {
    let input = "open ai chat gpt mac os"
    let output = service.cleanup(input, mode: .none)
    #expect(output == "OpenAI ChatGPT macOS")
  }

  @Test
  func cleanupLeavesSwiftCapitalizationToSmartModeOnly() {
    #expect(service.cleanup("swift", mode: .none) == "swift")
    #expect(service.cleanup("写 swift 代码", mode: .smart) == "写 Swift 代码")
  }

  @Test
  func cleanupNormalizesEverySpecifiedWhisperVariant() {
    let input = "whispers wispers whisper wisper WISPER"
    let output = service.cleanup(input, mode: .none)
    #expect(output == "Whisper Whisper Whisper Whisper Whisper")
  }

  @Test
  func cleanupNormalizesWhisperWhenGluedToChinese() {
    let output = service.cleanup("这段是 wisper 转写的", mode: .none)
    #expect(output == "这段是 Whisper 转写的")
  }

  @Test
  func cleanupKeepsLowercaseWhisperProperNouns() {
    // whisper.cpp / whisper-cli are the real project and binary names.
    #expect(service.cleanup("编译 whisper.cpp 的时候", mode: .none) == "编译 whisper.cpp 的时候")
    #expect(service.cleanup("run whisper-cli directly", mode: .none) == "run whisper-cli directly")
    #expect(service.cleanup("use whisper.", mode: .none) == "use Whisper.")
  }

  @Test
  func cleanupNormalizesPoolRequestButKeepsBarePool() {
    #expect(service.cleanup("open a pool request", mode: .none) == "open a pull request")
    #expect(service.cleanup("merge these pool requests", mode: .none) == "merge these pull requests")
    #expect(service.cleanup("we swim in the pool", mode: .none) == "we swim in the pool")
  }

  @Test
  func cleanupPreservesSentenceInitialCapitalWhenFixingPoolRequest() {
    #expect(service.cleanup("Pool request 已合并", mode: .none) == "Pull request 已合并")
  }

  @Test
  func cleanupNormalizesChineseBookingHomophone() {
    #expect(service.cleanup("定机票", mode: .none) == "订机票")
    #expect(service.cleanup("帮我定机票", mode: .none) == "帮我订机票")
    #expect(service.cleanup("先定酒店再定餐厅", mode: .none) == "先订酒店再订餐厅")
    #expect(service.cleanup("定个位子", mode: .none) == "订个位子")
    #expect(service.cleanup("定一个位子", mode: .none) == "订一个位子")
  }

  @Test
  func cleanupNormalizesChineseBookingHomophoneWithLeAndMeasureWord() {
    // The form that actually showed up in the long-audio eval sample.
    #expect(service.cleanup("晚上还要跟朋友吃饭就提前定了个位子", mode: .none) == "晚上还要跟朋友吃饭就提前订了个位子")
    #expect(service.cleanup("定了机票", mode: .none) == "订了机票")
    #expect(service.cleanup("定了一个房间", mode: .none) == "订了一个房间")
    #expect(service.cleanup("定了张车票", mode: .none) == "订了张车票")
    #expect(service.cleanup("定张车票", mode: .none) == "订张车票")
  }

  @Test
  func cleanupKeepsCommonChineseCompoundsEndingInDing() {
    #expect(service.cleanup("我决定机票明天买", mode: .none) == "我决定机票明天买")
    #expect(service.cleanup("一定要看门票价格", mode: .none) == "一定要看门票价格")
    #expect(service.cleanup("已经预定酒店了", mode: .none) == "已经预定酒店了")
    #expect(service.cleanup("确定车票信息", mode: .none) == "确定车票信息")
    #expect(service.cleanup("说不定机票会降价", mode: .none) == "说不定机票会降价")
    #expect(service.cleanup("绑定房间号", mode: .none) == "绑定房间号")
    // The widened 了 / measure-word middle must not reach past those same guards.
    #expect(service.cleanup("我们确定了个位子", mode: .none) == "我们确定了个位子")
    #expect(service.cleanup("已经预定了一个房间", mode: .none) == "已经预定了一个房间")
    #expect(service.cleanup("说不定了机票就便宜了", mode: .none) == "说不定了机票就便宜了")
  }

  @Test
  func cleanupSmartStripsTerminalPunctuationWhicheverMarkTheModelChose() {
    #expect(service.cleanup("今天天气不错。", mode: .smart) == "今天天气不错")
    #expect(service.cleanup("你到了吗？", mode: .smart) == "你到了吗")
    #expect(service.cleanup("好的！", mode: .smart) == "好的")
    #expect(service.cleanup("I'll do it later.", mode: .smart) == "I'll do it later")
    // Half-width marks go too, whether or not the mid-pipeline CJK conversion
    // has already turned them full-width.
    #expect(service.cleanup("你到了吗?", mode: .smart) == "你到了吗")
    #expect(service.cleanup("are you there?", mode: .smart) == "are you there")
  }

  @Test
  func cleanupSmartStripsATrailingRunOfTwoTerminalMarks() {
    #expect(service.cleanup("Really?!", mode: .smart) == "Really")
  }

  @Test
  func cleanupSmartKeepsEllipsisRunsOfThreeOrMore() {
    #expect(service.cleanup("让我想想...", mode: .smart) == "让我想想...")
    #expect(service.cleanup("让我想想……", mode: .smart) == "让我想想……")
  }

  @Test
  func cleanupSmartDoesNotReachInsideClosingQuotes() {
    #expect(service.cleanup("他说「好的。」", mode: .smart) == "他说「好的。」")
  }

  @Test
  func cleanupSmartKeepsInternalTerminalPunctuation() {
    #expect(service.cleanup("第一句。第二句。", mode: .smart) == "第一句。第二句")
  }

  @Test
  func cleanupSmartKeepsAPeriodTheUserDictatedAtTheEnd() {
    // The documented escape hatch: say 句号 when you do want a period.
    #expect(service.cleanup("今天先到这里句号", mode: .smart) == "今天先到这里。")
  }

  @Test
  func cleanupSmartKeepsOtherDictatedPunctuationAtTheEnd() {
    #expect(service.cleanup("先记一下逗号", mode: .smart) == "先记一下，")
    #expect(service.cleanup("重点如下冒号", mode: .smart) == "重点如下：")
  }

  @Test
  func cleanupSmartCollapsesAModelMarkInFrontOfADictatedOne() {
    // Model mark + spoken command must not leave a doubled 。.
    #expect(service.cleanup("结束了。句号", mode: .smart) == "结束了。")
  }

  @Test
  func cleanupSmartStillStripsModelMarksWhenTheCommandIsMidText() {
    #expect(service.cleanup("第一点句号第二点。", mode: .smart) == "第一点。第二点")
  }

  @Test
  func cleanupNoneKeepsTerminalPunctuationAsRawOutputEscapeHatch() {
    #expect(service.cleanup("今天天气不错。", mode: .none) == "今天天气不错。")
  }
}
