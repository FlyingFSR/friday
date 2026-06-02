import Foundation

enum ModelTier: String, Codable, CaseIterable, Identifiable {
  case base
  case small
  case medium
  case largeV3 = "large-v3"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .base:
      return "Base"
    case .small:
      return "Small"
    case .medium:
      return "Medium"
    case .largeV3:
      return "Large v3"
    }
  }
}

enum TextCleanupMode: String, Codable, CaseIterable {
  case none
  case light
  case smart

  static func fromLegacy(_ value: String?) -> TextCleanupMode {
    guard let value else {
      return .smart
    }
    let mode = TextCleanupMode(rawValue: value.lowercased()) ?? .smart
    return mode == .light ? .smart : mode
  }
}

struct FridaySettings: Codable {
  var hotkey: String
  var defaultModel: ModelTier
  var installedModels: [ModelTier]
  var autoStart: Bool
  var textCleanup: TextCleanupMode
  var pasteRestoreClipboard: Bool
  var blockSecureInput: Bool
  var retention: String
  var transcriptionLanguage: String

  static let `default` = FridaySettings(
    hotkey: "right_command",
    defaultModel: .medium,
    installedModels: [],
    autoStart: false,
    textCleanup: .smart,
    pasteRestoreClipboard: true,
    blockSecureInput: true,
    retention: "none",
    transcriptionLanguage: "auto"
  )

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hotkey = try container.decode(String.self, forKey: .hotkey)
    defaultModel = try container.decode(ModelTier.self, forKey: .defaultModel)
    installedModels = try container.decode([ModelTier].self, forKey: .installedModels)
    autoStart = try container.decode(Bool.self, forKey: .autoStart)
    if let cleanupMode = try? container.decode(TextCleanupMode.self, forKey: .textCleanup) {
      textCleanup = cleanupMode == .light ? .smart : cleanupMode
    } else {
      let legacyValue = try container.decodeIfPresent(String.self, forKey: .textCleanup)
      textCleanup = TextCleanupMode.fromLegacy(legacyValue)
    }
    pasteRestoreClipboard = try container.decode(Bool.self, forKey: .pasteRestoreClipboard)
    blockSecureInput = try container.decode(Bool.self, forKey: .blockSecureInput)
    retention = try container.decode(String.self, forKey: .retention)
    transcriptionLanguage = try container.decodeIfPresent(String.self, forKey: .transcriptionLanguage) ?? "auto"
  }

  init(
    hotkey: String,
    defaultModel: ModelTier,
    installedModels: [ModelTier],
    autoStart: Bool,
    textCleanup: TextCleanupMode,
    pasteRestoreClipboard: Bool,
    blockSecureInput: Bool,
    retention: String,
    transcriptionLanguage: String = "auto"
  ) {
    self.hotkey = hotkey
    self.defaultModel = defaultModel
    self.installedModels = installedModels
    self.autoStart = autoStart
    self.textCleanup = textCleanup
    self.pasteRestoreClipboard = pasteRestoreClipboard
    self.blockSecureInput = blockSecureInput
    self.retention = retention
    self.transcriptionLanguage = transcriptionLanguage
  }
}
