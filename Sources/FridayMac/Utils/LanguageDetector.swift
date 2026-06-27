import Foundation

enum LanguageDetector {
  /// Upper bound (exclusive) for scalars we treat as "Latin" — through the end
  /// of the Latin Extended-B block. Keeps CJK and other scripts out of the count.
  static let latinScalarUpperBound: UInt32 = 0x024F

  static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
    CharacterSet.letters.contains(scalar) && scalar.value < latinScalarUpperBound
  }

  /// CJK and Latin scalar counts for a string. Shared by language detection and
  /// diagnostics so the two can never drift apart.
  static func scriptCounts(in text: String) -> (cjk: Int, latin: Int) {
    let scalars = text.unicodeScalars
    let cjk = scalars.filter(CJKScript.isCJK).count
    let latin = scalars.filter(isLatinLetter).count
    return (cjk, latin)
  }

  static func detect(in text: String) -> DetectedLanguage {
    let counts = scriptCounts(in: text)
    if counts.cjk == 0 && counts.latin == 0 { return .unknown }
    if counts.cjk > 0 && counts.latin > 0 { return .mixed }
    if counts.cjk > 0 { return .zh }
    return .en
  }
}
