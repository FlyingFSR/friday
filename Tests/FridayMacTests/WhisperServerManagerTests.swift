import Testing
@testable import FridayMac

struct WhisperServerManagerTests {
  @Test
  func serverArgumentsIncludeVADWhenModelPathIsAvailable() {
    let args = WhisperServerManager.buildServerArguments(
      modelPath: "/tmp/ggml-medium.bin",
      vadModelPath: "/tmp/ggml-silero.bin",
      host: "127.0.0.1",
      port: 8178
    )

    #expect(args.contains("--vad"))
    #expect(args.contains("-vm"))
    #expect(args.contains("/tmp/ggml-silero.bin"))
    #expect(args.contains("-vmsd"))
    #expect(args.contains("15"))
    #expect(args.contains("-vsd"))
    #expect(args.contains("300"))
    #expect(args.contains("-vp"))
    #expect(args.contains("100"))
  }

  @Test
  func serverArgumentsOmitVADWhenModelPathIsMissing() {
    let args = WhisperServerManager.buildServerArguments(
      modelPath: "/tmp/ggml-medium.bin",
      vadModelPath: nil,
      host: "127.0.0.1",
      port: 8178
    )

    #expect(!args.contains("--vad"))
    #expect(!args.contains("-vm"))
  }
}
