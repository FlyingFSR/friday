// Derived from soniqo/speech-swift Sources/Qwen3ASR/QuantizedTextDecoder.swift and
// Sources/MLXCommon/{PreQuantizedEmbedding,SDPA,QuantizedMLP}.swift, commit cbcdfc6,
// Apache 2.0.
// Friday changes: plain structs built from checkpoint tensors with strict
// shape checks; embedding/LM head accept quantized or float weights; dimensions
// come from config.json. Architecture is unchanged: Qwen3 decoder with GQA,
// per-head q/k RMSNorm, split-half RoPE (MRoPE reduces to 1-D RoPE because audio
// and text positions are identical on all three axes), SwiGLU MLP, tied LM head.

import Foundation
import MLX
import MLXNN

struct RMSNormW {
    let weight: MLXArray
    let eps: Float
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLXFast.rmsNorm(x, weight: weight, eps: eps)
    }
}

/// Token embedding; quantized tables are dequantized row by row on lookup.
struct EmbeddingW {
    let weight: MLXArray
    let scales: MLXArray?
    let biases: MLXArray?
    let groupSize: Int
    let bits: Int

    func lookup(_ ids: MLXArray) -> MLXArray {
        let shape = ids.shape
        let flat = ids.flattened()
        let rows: MLXArray
        if let scales {
            rows = dequantized(weight[flat], scales: scales[flat], biases: biases?[flat],
                               groupSize: groupSize, bits: bits)
        } else {
            rows = weight[flat]
        }
        return rows.reshaped(shape + [-1])
    }

    /// Tied LM head: x @ E^T.
    func asLinear(_ x: MLXArray) -> MLXArray {
        if let scales {
            return quantizedMM(x, weight, scales: scales, biases: biases, transpose: true,
                               groupSize: groupSize, bits: bits)
        }
        return matmul(x, weight.T)
    }
}

struct DecoderLayer {
    let q, k, v, o, gate, up, down: LinearW
    let qNorm, kNorm, inputNorm, postNorm: RMSNormW
    let numHeads, numKVHeads, headDim: Int
    let ropeTheta: Float

    func callAsFunction(_ x: MLXArray, cache: inout (MLXArray, MLXArray)?) -> MLXArray {
        let (B, L) = (x.dim(0), x.dim(1))
        let h = inputNorm(x)
        var qh = qNorm(q(h).reshaped(B, L, numHeads, headDim)).transposed(0, 2, 1, 3)
        var kh = kNorm(k(h).reshaped(B, L, numKVHeads, headDim)).transposed(0, 2, 1, 3)
        var vh = v(h).reshaped(B, L, numKVHeads, headDim).transposed(0, 2, 1, 3)
        let offset = cache?.0.dim(2) ?? 0
        qh = MLXFast.RoPE(qh, dimensions: headDim, traditional: false, base: ropeTheta, scale: 1, offset: offset)
        kh = MLXFast.RoPE(kh, dimensions: headDim, traditional: false, base: ropeTheta, scale: 1, offset: offset)
        if let (pk, pv) = cache {
            kh = concatenated([pk, kh], axis: 2)
            vh = concatenated([pv, vh], axis: 2)
        }
        cache = (kh, vh)
        // Prefill (L > 1) is causal; a single decode step attends to everything cached.
        let a = MLXFast.scaledDotProductAttention(
            queries: qh, keys: kh, values: vh, scale: 1 / sqrt(Float(headDim)),
            mask: L > 1 ? .causal : .none)
        let y = x + o(a.transposed(0, 2, 1, 3).reshaped(B, L, numHeads * headDim))
        let m = postNorm(y)
        return y + down(silu(gate(m)) * up(m))
    }
}

public final class TextDecoder {
    let config: TextDecoderConfig
    let embed: EmbeddingW
    let layers: [DecoderLayer]
    let norm: RMSNormW
    let lmHead: LinearW?  // nil when tied to the embedding

    init(config c: TextDecoderConfig, weights w: WeightStore) throws {
        config = c
        let p = "model"
        if w.has("\(p).embed_tokens.scales") {
            let (wt, s, b, gs, bits) = try w.quantized("\(p).embed_tokens", rows: c.vocabSize, cols: c.hiddenSize)
            embed = EmbeddingW(weight: wt, scales: s, biases: b, groupSize: gs, bits: bits)
        } else {
            embed = EmbeddingW(weight: try w.float("\(p).embed_tokens.weight", [c.vocabSize, c.hiddenSize]),
                               scales: nil, biases: nil, groupSize: 0, bits: 0)
        }
        func rms(_ n: String, _ dim: Int) throws -> RMSNormW {
            RMSNormW(weight: try w.float("\(n).weight", [dim]), eps: c.rmsNormEps)
        }
        let qDim = c.numHeads * c.headDim, kvDim = c.numKVHeads * c.headDim
        layers = try (0 ..< c.numLayers).map { i in
            let lp = "\(p).layers.\(i)"
            return DecoderLayer(
                q: try w.linear("\(lp).self_attn.q_proj", inDim: c.hiddenSize, outDim: qDim, bias: false),
                k: try w.linear("\(lp).self_attn.k_proj", inDim: c.hiddenSize, outDim: kvDim, bias: false),
                v: try w.linear("\(lp).self_attn.v_proj", inDim: c.hiddenSize, outDim: kvDim, bias: false),
                o: try w.linear("\(lp).self_attn.o_proj", inDim: qDim, outDim: c.hiddenSize, bias: false),
                gate: try w.linear("\(lp).mlp.gate_proj", inDim: c.hiddenSize, outDim: c.intermediateSize, bias: false),
                up: try w.linear("\(lp).mlp.up_proj", inDim: c.hiddenSize, outDim: c.intermediateSize, bias: false),
                down: try w.linear("\(lp).mlp.down_proj", inDim: c.intermediateSize, outDim: c.hiddenSize, bias: false),
                qNorm: try rms("\(lp).self_attn.q_norm", c.headDim),
                kNorm: try rms("\(lp).self_attn.k_norm", c.headDim),
                inputNorm: try rms("\(lp).input_layernorm", c.hiddenSize),
                postNorm: try rms("\(lp).post_attention_layernorm", c.hiddenSize),
                numHeads: c.numHeads, numKVHeads: c.numKVHeads, headDim: c.headDim,
                ropeTheta: c.ropeTheta)
        }
        norm = try rms("\(p).norm", c.hiddenSize)
        if w.has("lm_head.weight") {
            lmHead = try w.linear("lm_head", inDim: c.hiddenSize, outDim: c.vocabSize, bias: false)
        } else if c.tieWordEmbeddings {
            lmHead = nil
        } else {
            throw Qwen3ASRError.badWeights("lm_head.weight missing and embeddings are not tied")
        }
    }

    /// Runs the decoder on input embeddings [1, L, hidden] and returns logits of the last position.
    func forward(_ embeds: MLXArray, cache: inout [(MLXArray, MLXArray)?]) -> MLXArray {
        var h = embeds
        for i in layers.indices {
            h = layers[i](h, cache: &cache[i])
        }
        let last = norm(h[0..., (h.dim(1) - 1)..., 0...])
        return lmHead.map { $0(last) } ?? embed.asLinear(last)
    }
}
