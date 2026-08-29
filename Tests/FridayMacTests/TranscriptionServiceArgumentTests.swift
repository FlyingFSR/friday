import Testing
@testable import FridayMac

struct TranscriptionServiceArgumentTests {
  @Test
  func mixedLanguagePromptIncludesPersonalVocabulary() {
    #expect(TranscriptionService.mixedLanguagePrompt.contains("Fable"))
    #expect(TranscriptionService.mixedLanguagePrompt.contains("relay"))
    #expect(TranscriptionService.mixedLanguagePrompt.contains("Sol"))
  }

  @Test
  func mixedLanguagePromptMatchesEvaluatedVariant() {
    // Exact "P6" text from the 2026-08 language-detection eval; changing it invalidates that run.
    #expect(
      TranscriptionService.mixedLanguagePrompt ==
        "Friday Codex Claude Fable relay Sol ChatGPT OpenAI Whisper whisper.cpp macOS Swift Git VAD React component " +
        "system prompt pull request voice input flow。" +
        "今天我用 Claude 写一个 React component，然后让 Codex review 这个 pull request。" +
        "I use Claude every day。"
    )
  }

  @Test
  func segmentJoinDropsNewlineBetweenChineseCharacters() {
    let output = TranscriptionService.joinTranscriptSegments("今天先做到\n这里")
    #expect(output == "今天先做到这里")
  }

  @Test
  func segmentJoinKeepsChineseClausesTightAcrossPunctuation() {
    let output = TranscriptionService.joinTranscriptSegments("我想把它做成中英版本。\n所以要准备两套。")
    #expect(output == "我想把它做成中英版本。所以要准备两套。")
  }

  @Test
  func segmentJoinInsertsSpaceBetweenEnglishSegments() {
    let output = TranscriptionService.joinTranscriptSegments("open a pull request.\nIf the review is clean")
    #expect(output == "open a pull request. If the review is clean")
  }

  @Test
  func segmentJoinInsertsSpaceAtMixedLanguageBoundaries() {
    #expect(TranscriptionService.joinTranscriptSegments("a mess.\n就是那种状态") == "a mess. 就是那种状态")
    #expect(TranscriptionService.joinTranscriptSegments("的版本\nSo we need slides") == "的版本 So we need slides")
  }

  @Test
  func segmentJoinKeepsChineseBracketsAndQuotesTight() {
    let output = TranscriptionService.joinTranscriptSegments("他说：\n「这个方案可以」\n然后就走了")
    #expect(output == "他说：「这个方案可以」然后就走了")
    #expect(TranscriptionService.joinTranscriptSegments("他说\n“好的”\n就走了") == "他说“好的”就走了")
  }

  @Test
  func segmentJoinKeepsChineseEllipsisAndDashTight() {
    #expect(TranscriptionService.joinTranscriptSegments("等一下……\n然后再说") == "等一下……然后再说")
    #expect(TranscriptionService.joinTranscriptSegments("这个方案——\n其实还行") == "这个方案——其实还行")
  }

  @Test
  func segmentJoinCollapsesRunsOfWhitespace() {
    #expect(TranscriptionService.joinTranscriptSegments("two  weeks") == "two weeks")
    #expect(TranscriptionService.joinTranscriptSegments("finish it  \n  first") == "finish it first")
    #expect(TranscriptionService.joinTranscriptSegments("  leading and trailing \n") == "leading and trailing")
  }

  @Test
  func segmentJoinLeavesSingleLineTextUnchanged() {
    let text = "Claude, Codex, Fable 和 Sol 都是我常用的工具。"
    #expect(TranscriptionService.joinTranscriptSegments(text) == text)
  }

  @Test
  func trailingHallucinationStripsShortEnglishTailAfterChineseText() {
    let output = TranscriptionService.stripTrailingHallucination("今天先做到这里 Thank you.")
    #expect(output == "今天先做到这里")
  }

  @Test
  func trailingHallucinationKeepsStandaloneEnglishText() {
    let output = TranscriptionService.stripTrailingHallucination("Thank you.")
    #expect(output == "Thank you.")
  }
}
