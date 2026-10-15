import Foundation
import Testing
@testable import FridayMac

struct ModelCatalogTests {
  @Test
  func catalogContainsOnlyQwen3ASR() {
    #expect(Array(ModelCatalog.all.keys) == [.qwen3ASR])
    // Whisper models are not offered for install anymore.
    #expect(ModelCatalog.all[.medium] == nil)
    #expect(ModelCatalog.all[.turbo] == nil)
    #expect(ModelCatalog.all[.largeV3] == nil)
  }

  @Test
  func qwenCatalogEntryPinsEveryFileTheEngineReads() throws {
    let qwen = try #require(ModelCatalog.all[.qwen3ASR])
    #expect(Set(qwen.files.map(\.name)) == [
      "config.json", "quantization_config.json", "tokenizer_config.json",
      "vocab.json", "merges.txt", "weights.safetensors",
    ])
    for file in qwen.files {
      #expect(file.sha256.count == 64)
      #expect(file.sizeBytes > 0)
    }
    // Pinned to one revision so the files cannot change underneath the checksums.
    #expect(qwen.baseURL.hasSuffix("/resolve/22c8abe6a6772122dda5905967d7496d1d3e8dd2"))
    let totalMB = qwen.files.map(\.sizeBytes).reduce(0, +) / 1_000_000
    #expect(abs(Int(totalMB) - qwen.approxSizeMB) < 20)
  }

  @Test
  func defaultSettingsMatchSpec() {
    let defaults = FridaySettings.default
    #expect(defaults.defaultModel == .qwen3ASR)
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
    #expect(settings.defaultModel == .medium)
  }
}
