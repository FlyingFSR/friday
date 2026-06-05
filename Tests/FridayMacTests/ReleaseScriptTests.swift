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
    #expect(script.contains(#"SHORT_VERSION="${FRIDAY_SHORT_VERSION:-0.3.1}""#))
  }

  @Test
  func installScriptReplacesExistingAppBeforeCopying() throws {
    let script = try read("scripts/install-local-app.sh")
    let replaceRange = try #require(script.range(of: #"rm -rf "$TARGET_APP""#))
    let copyRange = try #require(script.range(of: #"ditto "$SOURCE_APP" "$TARGET_APP""#))
    #expect(replaceRange.lowerBound < copyRange.lowerBound)
  }

  @Test
  func realSmokeDefaultsToMediumAndTurbo() throws {
    let script = try read("scripts/iterate_real_smoke.sh")
    #expect(script.contains(#"FRIDAY_REAL_SMOKE_MODELS", "medium,large-v3-turbo""#))
    #expect(script.contains(#"required_models = ["medium", "large-v3-turbo"]"#))
  }

  private func read(_ relativePath: String) throws -> String {
    let url = appRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
  }
}
