import Foundation

enum ModelTier: String, Codable, CaseIterable, Identifiable {
  /// The only model Friday 0.5 transcribes with.
  case qwen3ASR = "qwen3-asr-1.7b-8bit"
  // Whisper models from Friday 0.4. Kept so older settings files decode cleanly and
  // can be migrated on launch (see FridayController.migrateAwayFromRetiredModelsIfNeeded).
  case base
  case small
  case medium
  case largeV3 = "large-v3"
  case turbo = "large-v3-turbo"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .qwen3ASR:
      return "Qwen3-ASR 1.7B"
    case .base:
      return "Base"
    case .small:
      return "Small"
    case .medium:
      return "Medium"
    case .largeV3:
      return "Large v3"
    case .turbo:
      return "Turbo"
    }
  }
}

enum TextCleanupMode: String, Codable, CaseIterable {
  case none
  case smart

  // `light` was a third mode that no UI ever exposed and that decoding always
  // rewrote to `.smart`, so it is gone. Settings files written by older versions
  // can still say "light": every raw value that no longer maps to a case falls
  // back to `.smart` here instead of failing to decode.
  static func fromLegacy(_ value: String?) -> TextCleanupMode {
    guard let value else {
      return .smart
    }
    return TextCleanupMode(rawValue: value.lowercased()) ?? .smart
  }
}

enum PushToTalkKey: String, Codable, CaseIterable, Identifiable {
  case rightCommand = "right_command"
  case leftCommand = "left_command"
  case rightOption = "right_option"
  case leftOption = "left_option"
  case rightControl = "right_control"
  // For switching between the built-in Mac keyboard (has Right Command) and a
  // PC-style external keyboard (has Right Control instead): either key works.
  case rightCommandOrControl = "right_command_or_control"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .rightCommand:
      return "Right Command"
    case .leftCommand:
      return "Left Command"
    case .rightOption:
      return "Right Option"
    case .leftOption:
      return "Left Option"
    case .rightControl:
      return "Right Control"
    case .rightCommandOrControl:
      return "Right Command or Right Control"
    }
  }

  // Every physical key that counts as this push-to-talk key.
  var physicalKeys: [PushToTalkPhysicalKey] {
    switch self {
    case .rightCommand:
      return [.rightCommand]
    case .leftCommand:
      return [.leftCommand]
    case .rightOption:
      return [.rightOption]
    case .leftOption:
      return [.leftOption]
    case .rightControl:
      return [.rightControl]
    case .rightCommandOrControl:
      return [.rightCommand, .rightControl]
    }
  }
}

struct PushToTalkPhysicalKey: Equatable {
  // Values match the macOS virtual key constants in HIToolbox/Events.h.
  let keyCode: Int64
  let modifier: PushToTalkModifier

  static let rightCommand = PushToTalkPhysicalKey(keyCode: 0x36, modifier: .command)
  static let leftCommand = PushToTalkPhysicalKey(keyCode: 0x37, modifier: .command)
  static let rightOption = PushToTalkPhysicalKey(keyCode: 0x3D, modifier: .option)
  static let leftOption = PushToTalkPhysicalKey(keyCode: 0x3A, modifier: .option)
  static let rightControl = PushToTalkPhysicalKey(keyCode: 0x3E, modifier: .control)
}

enum PushToTalkModifier: Hashable {
  case command
  case option
  case control
}

struct FridaySettings: Codable {
  var defaultModel: ModelTier
  var installedModels: [ModelTier]
  var autoStart: Bool
  var textCleanup: TextCleanupMode
  var pasteRestoreClipboard: Bool
  var blockSecureInput: Bool
  var retention: String
  var transcriptionLanguage: String
  var pushToTalkKey: PushToTalkKey

  private enum CodingKeys: String, CodingKey {
    case defaultModel
    case installedModels
    case autoStart
    case textCleanup
    case pasteRestoreClipboard
    case blockSecureInput
    case retention
    case transcriptionLanguage
    case pushToTalkKey = "hotkey"
  }

  static let `default` = FridaySettings(
    defaultModel: .qwen3ASR,
    installedModels: [],
    autoStart: false,
    textCleanup: .smart,
    pasteRestoreClipboard: true,
    blockSecureInput: true,
    retention: "none",
    transcriptionLanguage: "auto",
    pushToTalkKey: .rightCommand
  )

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    defaultModel = try container.decode(ModelTier.self, forKey: .defaultModel)
    installedModels = try container.decode([ModelTier].self, forKey: .installedModels)
    autoStart = try container.decode(Bool.self, forKey: .autoStart)
    if let cleanupMode = try? container.decode(TextCleanupMode.self, forKey: .textCleanup) {
      textCleanup = cleanupMode
    } else {
      let legacyValue = try container.decodeIfPresent(String.self, forKey: .textCleanup)
      textCleanup = TextCleanupMode.fromLegacy(legacyValue)
    }
    pasteRestoreClipboard = try container.decode(Bool.self, forKey: .pasteRestoreClipboard)
    blockSecureInput = try container.decode(Bool.self, forKey: .blockSecureInput)
    retention = try container.decode(String.self, forKey: .retention)
    transcriptionLanguage = try container.decodeIfPresent(String.self, forKey: .transcriptionLanguage) ?? "auto"
    pushToTalkKey = (try? container.decode(PushToTalkKey.self, forKey: .pushToTalkKey)) ?? .rightCommand
  }

  init(
    defaultModel: ModelTier,
    installedModels: [ModelTier],
    autoStart: Bool,
    textCleanup: TextCleanupMode,
    pasteRestoreClipboard: Bool,
    blockSecureInput: Bool,
    retention: String,
    transcriptionLanguage: String = "auto",
    pushToTalkKey: PushToTalkKey = .rightCommand
  ) {
    self.defaultModel = defaultModel
    self.installedModels = installedModels
    self.autoStart = autoStart
    self.textCleanup = textCleanup
    self.pasteRestoreClipboard = pasteRestoreClipboard
    self.blockSecureInput = blockSecureInput
    self.retention = retention
    self.transcriptionLanguage = transcriptionLanguage
    self.pushToTalkKey = pushToTalkKey
  }
}
