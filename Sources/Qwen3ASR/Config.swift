// Derived from soniqo/speech-swift Sources/Qwen3ASR/Configuration.swift and
// AudioEncoder.swift (Qwen3AudioEncoderConfig), commit cbcdfc6, Apache 2.0.
// Friday changes: values are read from the model directory's config.json /
// quantization_config.json instead of hard-coded presets chosen by sniffing the
// model name; unused fields (forced aligner, dropout, 0.6B presets) removed.

import Foundation

public struct AudioEncoderConfig: Sendable {
    public var dModel: Int
    public var encoderAttentionHeads: Int
    public var encoderFFNDim: Int
    public var encoderLayers: Int
    public var numMelBins: Int
    public var maxSourcePositions: Int
    public var outputDim: Int
    public var downsampleHiddenSize: Int
    public var nWindow: Int
    public var nWindowInfer: Int
}

public struct TextDecoderConfig: Sendable {
    public var vocabSize: Int
    public var hiddenSize: Int
    public var numLayers: Int
    public var numHeads: Int
    public var numKVHeads: Int
    public var headDim: Int
    public var intermediateSize: Int
    public var rmsNormEps: Float
    public var ropeTheta: Float
    public var tieWordEmbeddings: Bool
}

public struct QuantizationConfig: Sendable {
    public var bits: Int
    public var groupSize: Int
}

public struct Qwen3ASRConfig: Sendable {
    public var audio: AudioEncoderConfig
    public var text: TextDecoderConfig
    public var audioTokenId: Int
    public var audioStartTokenId: Int
    public var audioEndTokenId: Int
    /// nil when the weights are not quantized.
    public var quantization: QuantizationConfig?

    public static func load(from directory: URL) throws -> Qwen3ASRConfig {
        let root = try readJSON(directory.appendingPathComponent("config.json"))
        // Official checkpoints nest everything under thinker_config.
        let thinker = (root["thinker_config"] as? [String: Any]) ?? root
        guard let a = thinker["audio_config"] as? [String: Any],
              let t = thinker["text_config"] as? [String: Any]
        else { throw Qwen3ASRError.badConfig("config.json has no audio_config/text_config") }

        let audio = AudioEncoderConfig(
            dModel: try int(a, "d_model"),
            encoderAttentionHeads: try int(a, "encoder_attention_heads"),
            encoderFFNDim: try int(a, "encoder_ffn_dim"),
            encoderLayers: try int(a, "encoder_layers"),
            numMelBins: try int(a, "num_mel_bins"),
            maxSourcePositions: try int(a, "max_source_positions"),
            outputDim: try int(a, "output_dim"),
            downsampleHiddenSize: try int(a, "downsample_hidden_size"),
            nWindow: try int(a, "n_window"),
            nWindowInfer: try int(a, "n_window_infer"))

        let text = TextDecoderConfig(
            vocabSize: try int(t, "vocab_size"),
            hiddenSize: try int(t, "hidden_size"),
            numLayers: try int(t, "num_hidden_layers"),
            numHeads: try int(t, "num_attention_heads"),
            numKVHeads: try int(t, "num_key_value_heads"),
            headDim: try int(t, "head_dim"),
            intermediateSize: try int(t, "intermediate_size"),
            rmsNormEps: try float(t, "rms_norm_eps"),
            ropeTheta: try float(t, "rope_theta"),
            tieWordEmbeddings: (t["tie_word_embeddings"] as? Bool) ?? false)

        guard audio.numMelBins == MelSpectrogram.nMels else {
            throw Qwen3ASRError.badConfig("num_mel_bins \(audio.numMelBins) != \(MelSpectrogram.nMels)")
        }

        var quant: QuantizationConfig?
        let qURL = directory.appendingPathComponent("quantization_config.json")
        if FileManager.default.fileExists(atPath: qURL.path) {
            let q = try readJSON(qURL)
            quant = QuantizationConfig(bits: try int(q, "bits"), groupSize: try int(q, "group_size"))
        } else if let q = root["quantization"] as? [String: Any] {
            quant = QuantizationConfig(bits: try int(q, "bits"), groupSize: try int(q, "group_size"))
        }

        return Qwen3ASRConfig(
            audio: audio, text: text,
            audioTokenId: try int(thinker, "audio_token_id"),
            audioStartTokenId: try int(thinker, "audio_start_token_id"),
            audioEndTokenId: try int(thinker, "audio_end_token_id"),
            quantization: quant)
    }
}

public enum Qwen3ASRError: Error, CustomStringConvertible {
    case badConfig(String)
    case badWeights(String)
    case badTokenizer(String)
    case badAudio(String)

    public var description: String {
        switch self {
        case .badConfig(let s): return "config: \(s)"
        case .badWeights(let s): return "weights: \(s)"
        case .badTokenizer(let s): return "tokenizer: \(s)"
        case .badAudio(let s): return "audio: \(s)"
        }
    }
}

func readJSON(_ url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw Qwen3ASRError.badConfig("\(url.lastPathComponent) is not a JSON object")
    }
    return obj
}

private func int(_ d: [String: Any], _ key: String) throws -> Int {
    guard let n = d[key] as? NSNumber else { throw Qwen3ASRError.badConfig("missing integer \(key)") }
    return n.intValue
}

private func float(_ d: [String: Any], _ key: String) throws -> Float {
    guard let n = d[key] as? NSNumber else { throw Qwen3ASRError.badConfig("missing number \(key)") }
    return n.floatValue
}
