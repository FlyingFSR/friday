import Foundation

enum RuntimeVersionInfo {
  /// The speech engine is compiled into the app, so its versions are fixed at build time.
  static let engine = "Qwen3-ASR 1.7B 8-bit (in-process)"
  static let mlxSwiftVersion = "0.32.3"

  static var diagnosticsSummary: String {
    "Runtime version: engine=\(engine), mlx-swift=\(mlxSwiftVersion)"
  }
}
