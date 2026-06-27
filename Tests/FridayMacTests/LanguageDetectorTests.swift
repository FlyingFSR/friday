import Testing
@testable import FridayMac

struct LanguageDetectorTests {
  @Test func detectsPureChineseAsZh() { #expect(LanguageDetector.detect(in: "你好世界") == .zh) }
  @Test func detectsPureEnglishAsEn() { #expect(LanguageDetector.detect(in: "hello world") == .en) }
  @Test func detectsMixedScriptAsMixed() { #expect(LanguageDetector.detect(in: "hello 你好") == .mixed) }
  @Test func detectsPunctuationAndDigitsAsUnknown() { #expect(LanguageDetector.detect(in: "123 !@# …") == .unknown) }
  @Test func scriptCountsCountsCjkAndLatinSeparately() {
    let counts = LanguageDetector.scriptCounts(in: "ab 你好")
    #expect(counts.cjk == 2); #expect(counts.latin == 2)
  }
}
