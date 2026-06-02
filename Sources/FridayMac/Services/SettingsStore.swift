import Foundation

actor SettingsStore {
  private let fileURL: URL
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init() {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let directory = appSupport.appendingPathComponent("Friday", isDirectory: true)
    self.fileURL = directory.appendingPathComponent("settings.json")
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  }

  func load() async -> FridaySettings {
    do {
      try ensureDirectory()
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        let defaults = FridaySettings.default
        try persist(defaults)
        return defaults
      }
      let data = try Data(contentsOf: fileURL)
      return try decoder.decode(FridaySettings.self, from: data)
    } catch {
      return .default
    }
  }

  func save(_ settings: FridaySettings) async {
    do {
      try ensureDirectory()
      try persist(settings)
    } catch {
      // Ignore write errors in first release; diagnostics UI still surfaces runtime issues.
    }
  }

  func update(_ mutate: (inout FridaySettings) -> Void) async -> FridaySettings {
    var current = await load()
    mutate(&current)
    await save(current)
    return current
  }

  private func ensureDirectory() throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  private func persist(_ settings: FridaySettings) throws {
    let data = try encoder.encode(settings)
    try data.write(to: fileURL, options: [.atomic])
  }
}
