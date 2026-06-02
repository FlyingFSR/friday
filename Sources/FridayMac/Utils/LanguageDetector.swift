import Foundation

enum LanguageDetector {
  static func detect(in text: String) -> DetectedLanguage {
    let scalars = text.unicodeScalars
    let cjkCount = scalars.filter { scalar in
      (0x4E00...0x9FFF).contains(scalar.value) ||
      (0x3400...0x4DBF).contains(scalar.value)
    }.count

    let latinCount = scalars.filter { scalar in
      CharacterSet.letters.contains(scalar) && scalar.value < 0x024F
    }.count

    if cjkCount == 0 && latinCount == 0 {
      return .unknown
    }

    if cjkCount > 0 && latinCount > 0 {
      return .mixed
    }

    if cjkCount > 0 {
      return .zh
    }

    return .en
  }
}
