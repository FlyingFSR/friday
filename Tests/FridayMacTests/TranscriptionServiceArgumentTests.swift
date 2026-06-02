import Testing
@testable import FridayMac

struct TranscriptionServiceArgumentTests {
  @Test
  func autoLanguageAddsVocabularyAndExamplePrompt() {
    let args = TranscriptionService.buildWhisperArguments(
      modelPath: "/tmp/model.bin",
      wavPath: "/tmp/input.wav",
      language: "auto",
      outputBasePath: "/tmp/out"
    )

    #expect(args.contains("-l"))
    #expect(args.contains("auto"))
    #expect(args.contains("-mc"))
    #expect(args.contains("0"))
    #expect(args.contains("-sow"))
    #expect(args.contains("--prompt"))
    #expect(args.contains { $0.contains("Friday Codex Claude ChatGPT OpenAI") })
    #expect(args.contains { $0.contains("今天我用 Claude 写一个 React component") })
    #expect(args.contains { $0.contains("让 Codex review 这个 pull request") })
    #expect(!args.contains { $0.contains("The speaker may switch") })
    #expect(!args.contains { $0.contains("Do not translate") })
    #expect(!args.contains { $0.contains("Use natural punctuation") })
    #expect(!args.contains("--carry-initial-prompt"))
    #expect(!args.contains("-nth"))
  }

  @Test
  func autoLanguageRetryConservativeUsesBoundedRecoveryFlags() {
    let args = TranscriptionService.buildWhisperArguments(
      modelPath: "/tmp/model.bin",
      wavPath: "/tmp/input.wav",
      language: "auto",
      outputBasePath: "/tmp/out",
      autoMode: .retryConservative
    )

    #expect(args.contains("-mc"))
    #expect(args.contains("-1"))
    #expect(args.contains("--prompt"))
    #expect(!args.contains("--carry-initial-prompt"))
  }

  @Test
  func explicitLanguageKeepsRequestedLanguageWithoutPrompt() {
    let args = TranscriptionService.buildWhisperArguments(
      modelPath: "/tmp/model.bin",
      wavPath: "/tmp/input.wav",
      language: "zh",
      outputBasePath: "/tmp/out"
    )

    #expect(args.contains("-l"))
    #expect(args.contains("zh"))
    #expect(!args.contains("--prompt"))
    #expect(!args.contains("-sow"))
  }

  @Test
  func includeJSONOutputAddsJSONFlags() {
    let args = TranscriptionService.buildWhisperArguments(
      modelPath: "/tmp/model.bin",
      wavPath: "/tmp/input.wav",
      language: "auto",
      outputBasePath: "/tmp/out",
      includeJSONOutput: true
    )

    #expect(args.contains("-oj"))
    #expect(args.contains("-ojf"))
  }

  @Test
  func trailingHallucinationStripsShortEnglishTailAfterChineseText() {
    let output = TranscriptionService.stripTrailingHallucination("今天先做到这里 Thank you.")
    #expect(output == "今天先做到这里")
  }

  @Test
  func trailingHallucinationKeepsStandaloneEnglishText() {
    let output = TranscriptionService.stripTrailingHallucination("Thank you.")
    #expect(output == "Thank you.")
  }
}
