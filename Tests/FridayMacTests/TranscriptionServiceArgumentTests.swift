import Testing
@testable import FridayMac

struct TranscriptionServiceArgumentTests {
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
