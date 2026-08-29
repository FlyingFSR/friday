import Foundation
import Testing
@testable import FridayMac

struct FridaySettingsHotkeyTests {
  @Test
  func settingsWithoutStoredHotkeyMigrateToRightCommand() throws {
    let data = Data("""
    {
      "defaultModel": "medium",
      "installedModels": ["medium"],
      "autoStart": false,
      "textCleanup": "smart",
      "pasteRestoreClipboard": true,
      "blockSecureInput": true,
      "retention": "none",
      "transcriptionLanguage": "auto"
    }
    """.utf8)

    let settings = try JSONDecoder().decode(FridaySettings.self, from: data)
    #expect(settings.pushToTalkKey == .rightCommand)
  }

  @Test
  func selectedHotkeyPersistsUsingLegacyCompatibleSettingsKey() throws {
    var settings = FridaySettings.default
    settings.pushToTalkKey = .leftOption

    let data = try JSONEncoder().encode(settings)
    let encoded = try #require(String(data: data, encoding: .utf8))
    let decoded = try JSONDecoder().decode(FridaySettings.self, from: data)

    #expect(encoded.contains("\"hotkey\":\"left_option\""))
    #expect(decoded.pushToTalkKey == .leftOption)
  }
}
