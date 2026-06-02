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
}
