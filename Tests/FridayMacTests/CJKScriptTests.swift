import Foundation
import Testing
@testable import FridayMac

struct CJKScriptTests {
  @Test
  func detectsUnifiedIdeographsAndExtensionA() {
    #expect(CJKScript.containsCJK("今天"))
    #expect(CJKScript.isCJK(Unicode.Scalar(0x3400)!))
  }

  @Test
  func doesNotTreatKanaAsCJKForChineseDetection() {
    #expect(!CJKScript.containsCJK("かな"))
  }

  @Test
  func exposesRegexCharacterClassFromSharedRanges() {
    #expect(CJKScript.regexCharacterClass == #"\u4E00-\u9FFF\u3400-\u4DBF"#)
  }
}
