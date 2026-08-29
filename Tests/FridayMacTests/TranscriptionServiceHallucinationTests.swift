import Testing
@testable import FridayMac

/// Characterization tests for the deterministic hallucination-stripping helpers.
///
/// The target workflow is Chinese + English dictation. Whisper sometimes emits
/// isolated Korean/Japanese runs or trailing "Thank you / Bye" artifacts from
/// silence. These helpers remove those without a model, so they must be safe on
/// legitimate mixed Chinese/English text. See issue #4 for the broader
/// mixed-language quality tracking.
struct TranscriptionServiceHallucinationTests {
  // MARK: - stripHallucinatedText (Korean / Japanese artifacts)

  @Test
  func stripsTrailingKoreanRunButKeepsChineseAndEnglish() {
    let output = TranscriptionService.stripHallucinatedText("Use the React component 안녕하세요")
    #expect(output == "Use the React component")
  }

  @Test
  func stripsTrailingJapaneseKanaRunButKeepsChineseAndEnglish() {
    let output = TranscriptionService.stripHallucinatedText("这是转录结果 こんにちは")
    #expect(output == "这是转录结果")
  }

  @Test
  func keepsCleanMixedChineseEnglishUnchanged() {
    let input = "今天我用 Claude 写一个 React component"
    #expect(TranscriptionService.stripHallucinatedText(input) == input)
  }

  @Test
  func keepsPlainEnglishUnchanged() {
    let input = "open the pull request and review it"
    #expect(TranscriptionService.stripHallucinatedText(input) == input)
  }

  @Test
  func keepsPunctuationBeforeAnInlineJapaneseRunAndLeavesOneJoiningSpace() {
    // The run's own separators go with it; the period ending the previous sentence does not.
    let output = TranscriptionService.stripHallucinatedText("the plan. ありがとう Next week")
    #expect(output == "the plan. Next week")
  }

  @Test
  func keepsPunctuationOnBothSidesOfAnInlineKoreanRun() {
    let output = TranscriptionService.stripHallucinatedText("Send the file. 안녕하세요 Then wait, please.")
    #expect(output == "Send the file. Then wait, please.")
  }

  @Test
  func joinsWithoutSpaceWhenTheRunSitsBetweenChineseCharacters() {
    let output = TranscriptionService.stripHallucinatedText("我先去 こんにちは 开个会")
    #expect(output == "我先去开个会")
  }

  @Test
  func stripsRunAtTheStartAndAtTheEndWithoutStraySpaces() {
    #expect(TranscriptionService.stripHallucinatedText("こんにちは open the pull request") == "open the pull request")
    #expect(TranscriptionService.stripHallucinatedText("open the pull request 안녕하세요") == "open the pull request")
  }

  @Test
  func stripsInteriorAndTrailingFullWidthPunctuationThatBelongsToTheRunItself() {
    let output = TranscriptionService.stripHallucinatedText("the plan. ありがとう、こんにちは。 Next week")
    #expect(output == "the plan. Next week")
  }

  @Test
  func stripsTrailingHalfWidthPunctuationThatBelongsToTheRunItself() {
    // Korean hallucinations end in a plain "." far more often than in "。"; leaving it
    // behind orphaned a stray mark next to the surviving Chinese.
    #expect(TranscriptionService.stripHallucinatedText("我说完了。 감사합니다.") == "我说完了。")
    #expect(
      TranscriptionService.stripHallucinatedText("会议结束了。 안녕하세요! 我们下次再聊。")
        == "会议结束了。我们下次再聊。"
    )
    #expect(
      TranscriptionService.stripHallucinatedText("这是一个 test。 한국어 환영합니다. 继续说中文。")
        == "这是一个 test。继续说中文。"
    )
  }

  // MARK: - stripTrailingHallucination (silence "Thank you / Bye" tails)

  @Test
  func stripsThanksForWatchingAfterSentencePunctuation() {
    let output = TranscriptionService.stripTrailingHallucination("OK we are done. Thanks for watching")
    #expect(output == "OK we are done.")
  }

  @Test
  func stripsTrailingTailAfterChinesePunctuation() {
    let output = TranscriptionService.stripTrailingHallucination("今天就先到这里。 Bye bye")
    #expect(output == "今天就先到这里。")
  }

  @Test
  func keepsLegitimateEnglishEndingThatIsNotAHallucinationTail() {
    // "component" is real content, not one of the stripped artifact phrases.
    let input = "I built a React component"
    #expect(TranscriptionService.stripTrailingHallucination(input) == input)
  }

  // MARK: - stripTrailingHallucination (Chinese video-outro tails)

  @Test
  func stripsChineseOutroTailAfterSentencePunctuation() {
    let output = TranscriptionService.stripTrailingHallucination("今天就先到这里。谢谢观看")
    #expect(output == "今天就先到这里。")
  }

  @Test
  func stripsTraditionalChineseOutroTailWithoutAnyPunctuation() {
    // Observed in the long-audio run: the buggy config emitted no punctuation at
    // all and still appended a Traditional-Chinese outro.
    let output = TranscriptionService.stripTrailingHallucination("我先在一楼喝了杯咖啡然后把邮件处理掉了謝謝觀看")
    #expect(output == "我先在一楼喝了杯咖啡然后把邮件处理掉了")
  }

  @Test
  func stripsEveryListedChineseOutroVariant() {
    let variants = [
      "谢谢观看", "謝謝觀看", "感谢收看", "感謝收看", "感谢观看", "感謝觀看",
      "谢谢收看", "謝謝收看", "请订阅", "請訂閱"
    ]
    for variant in variants {
      let output = TranscriptionService.stripTrailingHallucination("今天的记录到此为止。\(variant)。")
      #expect(output == "今天的记录到此为止。")
    }
  }

  @Test
  func keepsThanksToEveryoneWhichIsOrdinaryMessageClosing() {
    // 谢谢大家 is a normal way to close a message to a group, same tier as 谢谢.
    let input = "这个版本已经发出去了，谢谢大家"
    #expect(TranscriptionService.stripTrailingHallucination(input) == input)
  }

  @Test
  func stripsChineseOutroTailTogetherWithItsLeadingComma() {
    let output = TranscriptionService.stripTrailingHallucination("今天的分享就到这里，谢谢观看")
    #expect(output == "今天的分享就到这里")
  }

  @Test
  func keepsSentenceEndingPunctuationWhenStrippingChineseOutroTail() {
    let output = TranscriptionService.stripTrailingHallucination("今天的分享就到这里。谢谢观看")
    #expect(output == "今天的分享就到这里。")
  }

  @Test
  func stripsRepeatedChineseOutroTails() {
    let output = TranscriptionService.stripTrailingHallucination("今天先到这里。谢谢观看谢谢观看")
    #expect(output == "今天先到这里。")
  }

  @Test
  func keepsRepeatedChineseOutroPhraseWhenItIsTheEntireText() {
    let input = "谢谢观看谢谢观看"
    #expect(TranscriptionService.stripTrailingHallucination(input) == input)
  }

  @Test
  func keepsChineseOutroPhraseWhenItIsTheEntireText() {
    let input = "谢谢观看"
    #expect(TranscriptionService.stripTrailingHallucination(input) == input)
  }

  @Test
  func keepsBareThankYouInChineseAtEndOfDictation() {
    // Users legitimately end dictation with 谢谢; only the full outro phrases go.
    let input = "麻烦你帮我看一下这段代码，谢谢"
    #expect(TranscriptionService.stripTrailingHallucination(input) == input)
  }

  @Test
  func stripsOutroTailThatFollowsAClosingBracketOrQuote() {
    // Once joinTranscriptSegments removes the segment break, the tail sits directly
    // behind the closing mark, which used to fall outside the allowed context.
    #expect(TranscriptionService.stripTrailingHallucination("他说「就这样吧」谢谢观看") == "他说「就这样吧」")
    #expect(TranscriptionService.stripTrailingHallucination("会议纪要（第一版）谢谢观看") == "会议纪要（第一版）")
    #expect(TranscriptionService.stripTrailingHallucination("他说“好的” Thank you.") == "他说“好的”")
  }

  @Test
  func keepsChineseOutroPhraseThatIsNotAtTheEnd() {
    let input = "他在视频里说谢谢观看，然后就结束了"
    #expect(TranscriptionService.stripTrailingHallucination(input) == input)
  }
}
