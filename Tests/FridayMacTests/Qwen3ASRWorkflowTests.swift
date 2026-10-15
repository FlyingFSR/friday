import Foundation
import Testing
@testable import Qwen3ASR

/// The parts of the engine that run without the GPU: chunking and output parsing, both
/// translated from Alibaba's qwen-asr 0.0.6.
struct Qwen3ASRWorkflowTests {
  @Test
  func dictationLengthAudioIsOneChunk() {
    let audio = [Float](repeating: 0.1, count: 16_000 * 90)
    let chunks = OfficialChunker.split(audio)
    #expect(chunks.count == 1)
    #expect(chunks[0].count == audio.count)
  }

  @Test
  func audioUnderHalfASecondIsPaddedWithSilence() {
    let chunks = OfficialChunker.split([Float](repeating: 0.5, count: 3_000))
    #expect(chunks.count == 1)
    #expect(chunks[0].count == 8_000)
    #expect(chunks[0][2_999] == 0.5)
    #expect(chunks[0][3_000] == 0)
  }

  @Test
  func longAudioSplitsAtTheQuietSpotAndLosesNothing() {
    // 3 s of tone with a quiet stretch around 1.1 s; chunks of at most ~1 s.
    var audio = (0 ..< 48_000).map { Float(sin(Double($0) * 0.05)) * 0.5 }
    for i in 17_000 ..< 18_500 { audio[i] = 0.001 }
    let chunks = OfficialChunker.split(audio, maxChunkSec: 1, searchExpandSec: 0.2)
    #expect(chunks.count >= 3)
    #expect(Array(chunks.joined()) == audio)
    let firstCut = chunks[0].count
    #expect(firstCut >= 17_000 && firstCut < 18_500)
  }

  @Test
  func forcedLanguageOutputIsTheTranscript() {
    let (lang, text) = OutputParser.parse("  今天用 Claude 写代码。 ", forcedLanguage: "Chinese")
    #expect(lang == "Chinese")
    #expect(text == "今天用 Claude 写代码。")
  }

  @Test
  func detectedLanguageIsParsedFromTheModelPrefix() {
    let (lang, text) = OutputParser.parse("language English<asr_text>Hello there.", forcedLanguage: nil)
    #expect(lang == "English")
    #expect(text == "Hello there.")
    #expect(OutputParser.parse("language None<asr_text>", forcedLanguage: nil) == ("", ""))
  }

  @Test
  func pathologicalRepeatsCollapse() {
    #expect(OutputParser.fixRepetitions(String(repeating: "哈", count: 30)) == "哈")
    #expect(OutputParser.fixRepetitions("好的" + String(repeating: "对", count: 5)) == "好的对对对对对")
    #expect(OutputParser.fixRepetitions("开头" + String(repeating: "你好", count: 25) + "结尾") == "开头你好结尾")
  }
}
