import Foundation
import Testing

struct ReleaseScriptTests {
  private var appRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  @Test
  func buildScriptDefaultsToCurrentReleaseVersion() throws {
    let script = try read("scripts/build-local-app.sh")
    #expect(script.contains(#"SHORT_VERSION="${FRIDAY_SHORT_VERSION:-0.4.0}""#))
  }

  @Test
  func buildScriptBindsHomebrewVersionToSelectedWhisperRuntime() throws {
    let script = try read("scripts/build-local-app.sh")
    #expect(script.contains(#"brew --prefix whisper-cpp"#))
    #expect(script.contains(#"brew list --versions whisper-cpp"#))
    #expect(script.contains(#"if [[ "$server_real" != "$brew_prefix_real"/* ]]"#))
    #expect(script.contains("FRIDAY_WHISPER_CPP_VERSION"))
  }

  @Test
  func buildScriptFailsWhenVersionCannotBeDetermined() throws {
    let script = try read("scripts/build-local-app.sh")
    let detectionRange = try #require(
      script.range(of: #"WHISPER_CPP_VERSION="$(detect_whisper_cpp_version "$WHISPER_SERVER_SOURCE")""#)
    )
    let buildRange = try #require(script.range(of: #"echo "Building FridayMac in release mode...""#))
    #expect(detectionRange.lowerBound < buildRange.lowerBound)
    #expect(script.contains("Error: cannot determine whisper.cpp version"))
    #expect(script.contains("Error: Homebrew whisper.cpp version metadata does not match"))
  }

  @Test
  func buildScriptWritesAndGuardsBundledVersionRecord() throws {
    let script = try read("scripts/build-local-app.sh")
    let writeRange = try #require(
      script.range(of: #"printf '%s\n' "$WHISPER_CPP_VERSION" > "$WHISPER_VERSION_FILE""#)
    )
    let guardRange = try #require(
      script.range(of: #"if [[ ! -s "$WHISPER_VERSION_FILE" ]]"#)
    )
    let signRange = try #require(script.range(of: "sign_app_bundle_ad_hoc", options: .backwards))
    #expect(writeRange.lowerBound < guardRange.lowerBound)
    #expect(guardRange.lowerBound < signRange.lowerBound)
  }

  @Test
  func installScriptReplacesExistingAppBeforeCopying() throws {
    let script = try read("scripts/install-local-app.sh")
    let replaceRange = try #require(script.range(of: #"rm -rf "$TARGET_APP""#))
    let copyRange = try #require(script.range(of: #"ditto "$SOURCE_APP" "$TARGET_APP""#))
    #expect(replaceRange.lowerBound < copyRange.lowerBound)
  }

  @Test
  func realSmokeDefaultsToMediumOnly() throws {
    let script = try read("scripts/internal/iterate_real_smoke.sh")
    #expect(script.contains(#"FRIDAY_REAL_SMOKE_MODELS", "medium""#))
    #expect(script.contains(#"required_models = ["medium"]"#))
  }

  private func read(_ relativePath: String) throws -> String {
    let url = appRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
  }
}
