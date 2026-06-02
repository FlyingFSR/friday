import Foundation

final class WhisperServerManager: WhisperServerManaging {
  private var process: Process?
  private let port: Int = 8178
  private(set) var isReady = false

  var baseURL: URL {
    URL(string: "http://127.0.0.1:\(port)")!
  }

  func start(modelPath: String, vadModelPath: String? = nil) async throws {
    stop()
    killOrphanedServers()

    let binaryPath = try resolveWhisperServerBinary()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: binaryPath)
    proc.arguments = Self.buildServerArguments(
      modelPath: modelPath,
      vadModelPath: vadModelPath,
      host: "127.0.0.1",
      port: port
    )
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice

    try proc.run()
    process = proc

    try await waitUntilReady(timeout: 30)
  }

  func stop() {
    if let proc = process, proc.isRunning {
      proc.terminate()
    }
    process = nil
    isReady = false
  }

  private func waitUntilReady(timeout: TimeInterval) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    let healthURL = baseURL.appendingPathComponent("health")
    let session = URLSession(configuration: .ephemeral)

    while Date() < deadline {
      do {
        let (_, response) = try await session.data(from: healthURL)
        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
          isReady = true
          return
        }
      } catch {
        // Server not ready yet
      }
      try await Task.sleep(nanoseconds: 200_000_000)
    }

    stop()
    throw FridayError.whisperServerStartFailed
  }

  private func killOrphanedServers() {
    let lsof = Process()
    lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    lsof.arguments = ["-ti", "tcp:\(port)"]
    let pipe = Pipe()
    lsof.standardOutput = pipe
    lsof.standardError = FileHandle.nullDevice
    do {
      try lsof.run()
      lsof.waitUntilExit()
    } catch {
      return
    }
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    for line in output.split(separator: "\n") {
      if let pid = Int32(line.trimmingCharacters(in: .whitespaces)) {
        kill(pid, SIGTERM)
      }
    }
  }

  private func resolveWhisperServerBinary() throws -> String {
    if let bundled = Bundle.main.executableURL?
      .deletingLastPathComponent()
      .appendingPathComponent("whisper-server").path,
      FileManager.default.isExecutableFile(atPath: bundled) {
      return bundled
    }

    let candidates = [
      "/opt/homebrew/bin/whisper-server",
      "/usr/local/bin/whisper-server"
    ]

    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
      return candidate
    }

    let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for dir in pathValue.split(separator: ":") {
      let candidate = "\(dir)/whisper-server"
      if FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }

    throw FridayError.whisperServerNotFound
  }

  static func buildServerArguments(
    modelPath: String,
    vadModelPath: String?,
    host: String,
    port: Int
  ) -> [String] {
    var arguments = [
      "-m", modelPath,
      "--host", host,
      "--port", String(port),
      "--no-timestamps",
      "-et", "2.4",
      "-lpt", "-1.0",
      "-mc", "0",
      "-sow",
      "-sns"
    ]

    if let vadModelPath {
      arguments.append(contentsOf: [
        "--vad",
        "-vm", vadModelPath,
        "-vmsd", "15",
        "-vsd", "300",
        "-vp", "100"
      ])
    }

    return arguments
  }
}
