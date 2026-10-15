import Foundation
import Testing
@testable import FridayMac

struct RuntimeVersionInfoTests {
  @Test
  func diagnosticsSummaryNamesEngineAndMLXVersion() {
    #expect(
      RuntimeVersionInfo.diagnosticsSummary ==
        "Runtime version: engine=Qwen3-ASR 1.7B 8-bit (in-process), mlx-swift=0.32.3"
    )
  }

  @Test
  func mlxVersionMatchesPackagePin() throws {
    // The shader library fetched by scripts/fetch-mlx-metallib.sh is tied to this exact release.
    let manifest = try String(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    #expect(manifest.contains("mlx-swift\", exact: \"\(RuntimeVersionInfo.mlxSwiftVersion)\""))
  }
}
