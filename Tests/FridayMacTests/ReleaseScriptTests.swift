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
    #expect(script.contains(#"SHORT_VERSION="${FRIDAY_SHORT_VERSION:-0.5.0}""#))
  }

  @Test
  func buildScriptUsesNativeBuildSystemThatSkipsMetalSources() throws {
    // The default build system tries to compile mlx-swift's .metal files, which needs Xcode's
    // Metal compiler; the native one skips them and the shader library is bundled instead.
    let script = try read("scripts/build-local-app.sh")
    #expect(script.contains("swift build -c release --build-system native \\\n"))
    #expect(script.contains("swift build -c release --build-system native --show-bin-path"))
  }

  @Test
  func buildScriptBundlesAndGuardsShaderLibraryBeforeSigning() throws {
    let script = try read("scripts/build-local-app.sh")
    let fetchRange = try #require(script.range(of: #"METALLIB_SOURCE="$(bash "$SCRIPT_DIR/fetch-mlx-metallib.sh")""#))
    let buildRange = try #require(script.range(of: #"echo "Building FridayMac in release mode...""#))
    let copyRange = try #require(
      script.range(of: #"cp "$METALLIB_SOURCE" "$METALLIB_BUNDLE_DIR/default.metallib""#)
    )
    let guardRange = try #require(script.range(of: #"if [[ ! -s "$METALLIB_BUNDLE_DIR/default.metallib" ]]"#))
    let signRange = try #require(script.range(of: "sign_app_bundle_ad_hoc", options: .backwards))
    #expect(fetchRange.lowerBound < buildRange.lowerBound)
    #expect(copyRange.lowerBound < guardRange.lowerBound)
    #expect(guardRange.lowerBound < signRange.lowerBound)
    #expect(script.contains(#"METALLIB_BUNDLE_DIR="$RESOURCES_DIR/mlx-swift_Cmlx.bundle""#))
  }

  @Test
  func shaderLibraryIsPinnedToTheMLXCoreInPackageSwift() throws {
    // mlx-swift 0.32.3 vendors MLX core 0.32.2; its shader library must come from that release.
    let fetch = try read("scripts/fetch-mlx-metallib.sh")
    let manifest = try read("Package.swift")
    #expect(manifest.contains(#"mlx-swift", exact: "0.32.3""#))
    #expect(fetch.contains(#"VERSION="0.32.2""#))
    #expect(fetch.contains("3825fff379dbc107dd3413e564a06caeaa24819910ec49c0439e454c06a1b9b8"))
    #expect(fetch.contains("shasum -a 256 -c"))
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
