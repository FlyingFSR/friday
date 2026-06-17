import Foundation
import Testing
@testable import FridayMac

struct ModelCatalogTests {
  @Test
  func catalogContainsOnlyMedium() {
    #expect(ModelCatalog.all[.medium] != nil)
    // Retired models must not be offered for install anymore.
    #expect(ModelCatalog.all[.turbo] == nil)
    #expect(ModelCatalog.all[.largeV3] == nil)
  }

  @Test
  func catalogSizeEstimatesMatchPublishedWhisperDownloads() throws {
    let medium = try #require(ModelCatalog.all[.medium])

    #expect(medium.approxSizeMB == 1530)
  }

  @Test
  func defaultSettingsMatchSpec() {
    let defaults = FridaySettings.default
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
