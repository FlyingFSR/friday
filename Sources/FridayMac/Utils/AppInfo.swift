import Foundation

/// App-level metadata read from the bundle's Info.plist.
enum AppInfo {
  /// The marketing version (e.g. "v0.3.4"). Falls back to "dev" when running
  /// without a bundle (e.g. `swift run`), where no Info.plist is present.
  static var versionLabel: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    return version.map { "v\($0)" } ?? "dev"
  }
}
