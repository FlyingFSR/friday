import Foundation

enum CJKScript {
  static let regexCharacterClass = #"\u4E00-\u9FFF\u3400-\u4DBF"#

  static func containsCJK(_ text: String) -> Bool {
    text.unicodeScalars.contains(where: isCJK)
  }

  static func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains(where: isCJK)
  }

  static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x4E00...0x9FFF, 0x3400...0x4DBF:
      return true
    default:
      return false
    }
  }
}
