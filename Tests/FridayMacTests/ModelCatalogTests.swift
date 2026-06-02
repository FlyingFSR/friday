import Foundation
import Testing
@testable import FridayMac

struct ModelCatalogTests {
  @Test
  func catalogContainsRequiredModels() {
    #expect(ModelCatalog.all[.base] != nil)
    #expect(ModelCatalog.all[.small] != nil)
    #expect(ModelCatalog.all[.medium] != nil)
    #expect(ModelCatalog.all[.largeV3] != nil)
  }

  @Test
  func catalogSizeEstimatesMatchPublishedWhisperDownloads() throws {
    let medium = try #require(ModelCatalog.all[.medium])
    let largeV3 = try #require(ModelCatalog.all[.largeV3])

    #expect(medium.approxSizeMB == 1530)
    #expect(largeV3.approxSizeMB == 3100)
  }

  @Test
  func defaultSettingsMatchSpec() {
    let defaults = FridaySettings.default
    #expect(defaults.hotkey == "right_command")
    #expect(defaults.defaultModel == .medium)
    #expect(defaults.textCleanup == .smart)
    #expect(defaults.pasteRestoreClipboard)
    #expect(defaults.blockSecureInput)
    #expect(defaults.retention == "none")
  }

  @Test
  func legacyLightCleanupSettingsUpgradeToSmart() throws {
    let data = Data("""
    {
      "hotkey": "right_command",
      "defaultModel": "medium",
      "installedModels": ["medium"],
      "autoStart": false,
      "textCleanup": "light",
      "pasteRestoreClipboard": true,
      "blockSecureInput": true,
      "retention": "none",
      "transcriptionLanguage": "auto"
    }
    """.utf8)

    let settings = try JSONDecoder().decode(FridaySettings.self, from: data)
    #expect(settings.textCleanup == .smart)
  }
}
