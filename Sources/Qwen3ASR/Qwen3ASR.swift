// Derived from soniqo/speech-swift Sources/Qwen3ASR/Qwen3ASR.swift (non-streaming
// single-input path), commit cbcdfc6, Apache 2.0.
// Friday changes, so the outer workflow matches Alibaba's qwen-asr 0.0.6:
// - loads only from a local directory (no Hugging Face download, no global
//   Metal wired-memory / cache-limit changes, no memory warnings);
// - prompt follows the official chat template; "<asr_text>" is appended only
//   when a language is forced (the original always appended it);
// - removed the automatic no-repeat-3-gram constraint on >15 s audio, sampling,
//   repetition penalty and the batched decoders; decoding is plain greedy and
//   stops on either end token (151643 / 151645);
// - audio is split only above 1200 s, chunks under 0.5 s are padded with silence;
// - token budget is the official 512, raised to 8 tokens per second of audio for
//   dictation longer than 64 s (Friday-specific; Chinese measured ~2.5 tokens/s);
// - output gets the official clean-up (collapse pathological repeats, parse
//   "language X<asr_text>").
// Parity with mlx-qwen3-asr and the official workflow is documented in
// docs/qwen3-asr-swift-port-2026-10.md.

import Foundation
import MLX

public struct TranscriptionOutput: Sendable {
    public var text: String
    public var language: String
    /// Why each chunk stopped: "eos" or "length".
    public var finishReasons: [String]

    public init(text: String, language: String, finishReasons: [String]) {
        self.text = text
        self.language = language
        self.finishReasons = finishReasons
    }
}

/// Not thread-safe: call from one task at a time (Friday wraps it in an actor).
public final class Qwen3ASRModel {
    public let config: Qwen3ASRConfig
    public let tokenizer: Qwen3Tokenizer
    let encoder: AudioEncoder
    let decoder: TextDecoder
    let imStart: Int, imEnd: Int, endOfText: Int
    let eosIds: Set<Int>

    public init(directory: URL, dtype: DType = .float16) throws {
        config = try Qwen3ASRConfig.load(from: directory)
        tokenizer = try Qwen3Tokenizer(directory: directory)
        let weights = try WeightStore(directory: directory, quant: config.quantization, dtype: dtype)
        encoder = try AudioEncoder(config: config.audio, weights: weights)
        decoder = try TextDecoder(config: config.text, weights: weights)
        try weights.checkAllUsed()
        // Materialize every weight now, on the loading thread: an unevaluated MLX
        // graph cannot be evaluated later from a different thread.
        eval(weights.consumedArrays + [encoder.positions])
        weights.release()

        let tok = tokenizer
        func special(_ t: String) throws -> Int {
            guard let id = tok.tokenId(t) else { throw Qwen3ASRError.badTokenizer("no \(t)") }
            return id
        }
        imStart = try special("<|im_start|>")
        imEnd = try special("<|im_end|>")
        endOfText = try special("<|endoftext|>")
        eosIds = [endOfText, imEnd]
        guard try special("<|audio_pad|>") == config.audioTokenId,
              try special("<|audio_start|>") == config.audioStartTokenId,
              try special("<|audio_end|>") == config.audioEndTokenId
        else { throw Qwen3ASRError.badTokenizer("audio token ids disagree with config.json") }
    }

    /// Prompt token ids, with `nAudio` audio placeholders.
    public func promptTokens(nAudio: Int, language: String?, context: String) -> [Int] {
        let nl = tokenizer.encode("\n")
        var t = [imStart] + tokenizer.encode("system\n")
        if !context.isEmpty { t += tokenizer.encode(context) }
        t += [imEnd] + nl
        t += [imStart] + tokenizer.encode("user\n") + [config.audioStartTokenId]
        t += Array(repeating: config.audioTokenId, count: nAudio)
        t += [config.audioEndTokenId, imEnd] + nl
        t += [imStart] + tokenizer.encode("assistant\n")
        if let language, !language.isEmpty { t += tokenizer.encode("language \(language)<asr_text>") }
        return t
    }

    /// 16 kHz mono float samples in [-1, 1]. `language` is the full English name
    /// ("Chinese"), as in the official template; nil lets the model detect it.
    /// `shouldCancel` is checked before every decoding step.
    public func transcribe(
        _ audio: [Float], language: String?, context: String = "",
        shouldCancel: () -> Bool = { false }
    ) throws -> TranscriptionOutput {
        var texts: [String] = []
        var languages: [String] = []
        var reasons: [String] = []
        defer { Memory.clearCache() }
        for chunk in OfficialChunker.split(audio) {
            let r = try transcribeChunk(chunk, language: language, context: context, shouldCancel: shouldCancel)
            texts.append(r.text)
            if let l = r.language, !l.isEmpty, l != languages.last { languages.append(l) }
            reasons.append(r.reason)
        }
        return TranscriptionOutput(
            text: texts.joined(), language: languages.joined(separator: ","), finishReasons: reasons)
    }

    func transcribeChunk(
        _ audio: [Float], language: String?, context: String, shouldCancel: () -> Bool
    ) throws -> (text: String, language: String?, reason: String) {
        let mel = try MelSpectrogram.compute(audio)
        let audioEmbeds = encoder(mel)  // [nAudio, hidden]
        let nAudio = audioEmbeds.dim(0)
        let ids = promptTokens(nAudio: nAudio, language: language, context: context)
        let start = ids.firstIndex(of: config.audioTokenId)!

        var embeds = decoder.embed.lookup(MLXArray(ids.map { Int32($0) }).expandedDimensions(axis: 0))
        embeds = concatenated([
            embeds[0..., 0 ..< start, 0...],
            audioEmbeds.asType(embeds.dtype).expandedDimensions(axis: 0),
            embeds[0..., (start + nAudio)..., 0...],
        ], axis: 1)

        let seconds = Double(audio.count) / Double(MelSpectrogram.sampleRate)
        let maxNew = max(512, Int(ceil(seconds * 8)))
        var cache = [(MLXArray, MLXArray)?](repeating: nil, count: decoder.layers.count)
        var logits = decoder.forward(embeds, cache: &cache)
        var token = Int(argMax(logits, axis: -1).asType(.int32).item(Int32.self))
        var generated = [token]
        while generated.count < maxNew, !eosIds.contains(token) {
            if shouldCancel() { throw CancellationError() }
            let next = decoder.embed.lookup(MLXArray([Int32(token)]).reshaped(1, 1))
            logits = decoder.forward(next, cache: &cache)
            token = Int(argMax(logits, axis: -1).asType(.int32).item(Int32.self))
            generated.append(token)
        }
        var reason = "length"
        if let last = generated.last, eosIds.contains(last) {
            reason = "eos"
            generated.removeLast()
        }
        let (lang, text) = OutputParser.parse(tokenizer.decode(generated), forcedLanguage: language)
        return (text, lang, reason)
    }
}
