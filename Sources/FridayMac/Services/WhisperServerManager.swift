import Foundation

final class WhisperServerManager: WhisperServerManaging {
  private var process: Process?
  private let port: Int = 8178
  private(set) var isReady = false
  // Remembered after a successful launch so restart() can recover the server
  // without re-deriving (and re-checksumming) the model path. Mutated only from
  // the launch path, which callers invoke from the main actor.
  private var lastModelPath: String?
  private var lastVADModelPath: String?

  var baseURL: URL {
    URL(string: "http://127.0.0.1:\(port)")!
  }

  func start(modelPath: String, vadModelPath: String? = nil) async throws {
    try await launch(modelPath: modelPath, vadModelPath: vadModelPath, timeout: 30)
  }

  func restart() async throws {
    guard let lastModelPath else {
      throw FridayError.whisperServerStartFailed
    }
    // Tighter timeout than a cold start: the model was just resident, so a warm
    // relaunch is fast, and a stuck recovery should fail quickly rather than
    // leave the user staring at the HUD.
    try await launch(modelPath: lastModelPath, vadModelPath: lastVADModelPath, timeout: 20)
  }

  private func launch(modelPath: String, vadModelPath: String?, timeout: TimeInterval) async throws {
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

    try await waitUntilReady(timeout: timeout)
    lastModelPath = modelPath
    lastVADModelPath = vadModelPath
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
    lsof.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-F", "pc"]
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
    for pid in Self.whisperServerPIDs(from: output) {
      kill(pid, SIGTERM)
    }
  }

  static func whisperServerPIDs(from lsofOutput: String) -> [Int32] {
    var currentPID: Int32?
    var pids: [Int32] = []

    for rawLine in lsofOutput.split(separator: "\n") {
      let line = String(rawLine)
      if line.hasPrefix("p") {
        currentPID = Int32(line.dropFirst().trimmingCharacters(in: .whitespaces))
      } else if line.hasPrefix("c") {
        let command = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        if command == "whisper-server", let currentPID {
          pids.append(currentPID)
        }
      }
    }

    return pids
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
      "-et", "2.4",
      "-lpt", "-1.0",
      // Two flags must stay out of this list:
      // - "-mc 0" (long form "--max-context 0") silently disables the initial prompt entirely,
      //   which degrades punctuation and English accuracy.
      // - "--no-timestamps" (long form of "-nt") caused whole Chinese insertion sentences to be
      //   dropped from English-primary audio and English passages to be mistranslated. With it
      //   gone the response text arrives split into segments, which
      //   TranscriptionService.joinTranscriptSegments reassembles.
      // These flags and TranscriptionService.mixedLanguagePrompt were validated as one
      // configuration, so changing any part means re-running the eval matrix. The configuration
      // is not free: measured against the pre-change baseline it costs roughly 9% latency on
      // short dictation and 23% on long audio, and yields slightly more traditional-character
      // output (Friday has no simplified/traditional normalization).
      // See docs/language-detection-findings-2026-08.md.
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
