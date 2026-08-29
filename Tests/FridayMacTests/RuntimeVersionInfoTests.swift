import Foundation
import Testing
@testable import FridayMac

struct RuntimeVersionInfoTests {
  @Test
  func normalizesSingleLineVersionRecord() {
    #expect(RuntimeVersionInfo.normalizedWhisperCPPVersion(from: "  1.8.3\n") == "1.8.3")
  }

  @Test
  func rejectsMissingBlankOrAmbiguousVersionRecords() {
    #expect(RuntimeVersionInfo.normalizedWhisperCPPVersion(from: nil) == nil)
    #expect(RuntimeVersionInfo.normalizedWhisperCPPVersion(from: " \n\t") == nil)
    #expect(RuntimeVersionInfo.normalizedWhisperCPPVersion(from: "1.8.2\n1.8.3\n") == nil)
  }

  @Test
  func diagnosticsSummaryIncludesKnownVersion() {
    let summary = RuntimeVersionInfo.diagnosticsSummary(whisperCPPVersion: "1.8.3")
    #expect(summary == "Runtime version: whisper.cpp=1.8.3")
  }

  @Test
  func diagnosticsSummaryIsHonestWhenVersionIsUnavailable() {
    let summary = RuntimeVersionInfo.diagnosticsSummary(whisperCPPVersion: nil)
    #expect(summary == "Runtime version: whisper.cpp=unavailable")
  }

  @Test
  func readsVersionFromBundleResource() throws {
    let fileManager = FileManager.default
    let bundleURL = fileManager.temporaryDirectory
      .appendingPathComponent("FridayRuntimeVersion-\(UUID().uuidString)")
      .appendingPathExtension("bundle")
    let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
    let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
    defer { try? fileManager.removeItem(at: bundleURL) }

    try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
    let infoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>com.fw.friday.runtime-version-tests</string>
    </dict>
    </plist>
    """
    try infoPlist.write(
      to: contentsURL.appendingPathComponent("Info.plist"),
      atomically: true,
      encoding: .utf8
    )
    try "1.8.3\n".write(
      to: resourcesURL.appendingPathComponent(RuntimeVersionInfo.whisperVersionResourceName),
      atomically: true,
      encoding: .utf8
    )

    let bundle = try #require(Bundle(url: bundleURL))
    #expect(RuntimeVersionInfo.whisperCPPVersion(in: bundle) == "1.8.3")
  }
}
