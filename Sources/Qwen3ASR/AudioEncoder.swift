// Derived from soniqo/speech-swift Sources/Qwen3ASR/AudioEncoder.swift,
// commit cbcdfc6, Apache 2.0.
// Friday changes:
// - layers are plain structs built from checkpoint tensors (see Weights.swift);
//   linears may be quantized (the mlx-qwen3-asr format quantizes the encoder);
// - the sinusoidal position table is cast to the activation dtype (the original
//   added a float32 table, silently promoting the whole encoder to float32);
// - mel input is cast to the model dtype; fp16 activations are clamped after each
//   layer as in the official/reference encoder;
// - windowed attention runs per window instead of building a dense L x L mask;
// - the unused processConvChunk helper (with a different flatten order) is gone.
// Chunking semantics are unchanged: 100-frame chunks, conv stem per chunk, a short
// tail is zero-padded to 100 frames only when a full chunk exists, position
// embeddings restart at 0 in every chunk, attention windows of 8 chunks.

import Foundation
import MLX
import MLXNN

struct Conv2dW {
    let weight: MLXArray  // [out, kH, kW, in]
    let bias: MLXArray
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        conv2d(x, weight, stride: 2, padding: 1) + bias
    }
}

struct LayerNormW {
    let weight: MLXArray
    let bias: MLXArray
    let eps: Float
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLXFast.layerNorm(x, weight: weight, bias: bias, eps: eps)
    }
}

struct AudioEncoderLayer {
    let q, k, v, out, fc1, fc2: LinearW
    let attnNorm, finalNorm: LayerNormW
    let numHeads: Int

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let (B, L, D) = (x.dim(0), x.dim(1), x.dim(2))
        let headDim = D / numHeads
        let h = attnNorm(x)
        let qh = q(h).reshaped(B, L, numHeads, headDim).transposed(0, 2, 1, 3)
        let kh = k(h).reshaped(B, L, numHeads, headDim).transposed(0, 2, 1, 3)
        let vh = v(h).reshaped(B, L, numHeads, headDim).transposed(0, 2, 1, 3)
        let a = MLXFast.scaledDotProductAttention(
            queries: qh, keys: kh, values: vh, scale: 1 / sqrt(Float(headDim)), mask: .none)
        var y = x + out(a.transposed(0, 2, 1, 3).reshaped(B, L, D))
        y = y + fc2(gelu(fc1(finalNorm(y))))
        if y.dtype == .float16 {
            let c = Float(65504.0 - 1000.0)
            y = clip(y, min: -c, max: c)
        }
        return y
    }
}

public final class AudioEncoder {
    let config: AudioEncoderConfig
    let conv1, conv2, conv3: Conv2dW
    let convOut, proj1, proj2: LinearW
    let lnPost: LayerNormW
    let layers: [AudioEncoderLayer]
    let positions: MLXArray  // [maxSourcePositions, dModel], model dtype
    let dtype: DType

    init(config c: AudioEncoderConfig, weights w: WeightStore) throws {
        config = c
        dtype = w.dtype
        let p = "audio_tower"
        let dhs = c.downsampleHiddenSize
        func conv(_ n: String, _ inC: Int) throws -> Conv2dW {
            Conv2dW(weight: try w.float("\(p).\(n).weight", [dhs, 3, 3, inC]),
                    bias: try w.float("\(p).\(n).bias", [dhs]))
        }
        func norm(_ n: String) throws -> LayerNormW {
            LayerNormW(weight: try w.float("\(n).weight", [c.dModel]),
                       bias: try w.float("\(n).bias", [c.dModel]), eps: 1e-5)
        }
        conv1 = try conv("conv2d1", 1)
        conv2 = try conv("conv2d2", dhs)
        conv3 = try conv("conv2d3", dhs)
        let freqAfterConv = c.numMelBins / 8
        convOut = try w.linear("\(p).conv_out", inDim: dhs * freqAfterConv, outDim: c.dModel, bias: false)
        lnPost = try norm("\(p).ln_post")
        proj1 = try w.linear("\(p).proj1", inDim: c.dModel, outDim: c.dModel, bias: true)
        proj2 = try w.linear("\(p).proj2", inDim: c.dModel, outDim: c.outputDim, bias: true)
        layers = try (0 ..< c.encoderLayers).map { i in
            let lp = "\(p).layers.\(i)"
            return AudioEncoderLayer(
                q: try w.linear("\(lp).self_attn.q_proj", inDim: c.dModel, outDim: c.dModel, bias: true),
                k: try w.linear("\(lp).self_attn.k_proj", inDim: c.dModel, outDim: c.dModel, bias: true),
                v: try w.linear("\(lp).self_attn.v_proj", inDim: c.dModel, outDim: c.dModel, bias: true),
                out: try w.linear("\(lp).self_attn.out_proj", inDim: c.dModel, outDim: c.dModel, bias: true),
                fc1: try w.linear("\(lp).fc1", inDim: c.dModel, outDim: c.encoderFFNDim, bias: true),
                fc2: try w.linear("\(lp).fc2", inDim: c.encoderFFNDim, outDim: c.dModel, bias: true),
                attnNorm: try norm("\(lp).self_attn_layer_norm"),
                finalNorm: try norm("\(lp).final_layer_norm"),
                numHeads: c.encoderAttentionHeads)
        }
        // Official SinusoidsPositionEmbedding: increment = log(10000) / (half - 1),
        // [sin | cos] concatenated (not interleaved), computed in float32.
        let half = c.dModel / 2
        let inc = log(Float(10000)) / Float(half - 1)
        let invTimescales = exp(MLXArray(0 ..< half).asType(.float32) * -inc)
        let scaled = MLXArray(0 ..< c.maxSourcePositions).asType(.float32).expandedDimensions(axis: 1)
            * invTimescales.expandedDimensions(axis: 0)
        positions = concatenated([sin(scaled), cos(scaled)], axis: 1).asType(w.dtype)
    }

    private func convStem(_ x: MLXArray) -> MLXArray {
        gelu(conv3(gelu(conv2(gelu(conv1(x))))))
    }

    /// mel: [nMels, frames] -> [tokens, outputDim]
    func callAsFunction(_ melIn: MLXArray) -> MLXArray {
        let mel = melIn.asType(dtype)
        let nMels = mel.dim(0)
        let totalFrames = mel.dim(1)
        let chunk = config.nWindow * 2
        var convOutputs: [MLXArray] = []
        var chunkTokens: [Int] = []

        let nFull = totalFrames / chunk
        if nFull > 0 {
            let full = mel[0..., 0 ..< (nFull * chunk)]
                .reshaped(nMels, nFull, chunk).transposed(1, 0, 2)  // [nFull, mel, chunk]
            var x = convStem(full.expandedDimensions(axis: -1))  // [nFull, F', T', C]
            let (F, T, C) = (x.dim(1), x.dim(2), x.dim(3))
            // Channel-major flatten to match the PyTorch conv_out weight layout.
            x = x.transposed(0, 2, 3, 1).reshaped(nFull * T, C * F)
            convOutputs.append(x)
            chunkTokens += Array(repeating: T, count: nFull)
        }
        if nFull * chunk < totalFrames {
            var tail = mel[0..., (nFull * chunk)...]
            let validTokens = (tail.dim(1) + 7) / 8
            if nFull > 0 {
                tail = padded(tail, widths: [.init((0, 0)), .init((0, chunk - tail.dim(1)))])
            }
            var x = convStem(tail.expandedDimensions(axis: 0).expandedDimensions(axis: -1))
            x = x[0..., 0..., 0 ..< validTokens, 0...]
            let (F, T, C) = (x.dim(1), x.dim(2), x.dim(3))
            convOutputs.append(x.transposed(0, 2, 3, 1).reshaped(T, C * F))
            chunkTokens.append(T)
        }

        var x = convOut(concatenated(convOutputs, axis: 0))  // [tokens, dModel]
        x = x + concatenated(chunkTokens.map { positions[0 ..< $0] }, axis: 0)

        let total = x.dim(0)
        let tokensPerWindow = chunkTokens[0] * (config.nWindowInfer / chunk)
        var bounds = [0]
        while bounds.last! < total { bounds.append(min(bounds.last! + tokensPerWindow, total)) }

        x = x.expandedDimensions(axis: 0)
        for layer in layers {
            if bounds.count <= 2 {
                x = layer(x)
            } else {
                let parts = (0 ..< bounds.count - 1).map { i in
                    layer(x[0..., bounds[i] ..< bounds[i + 1], 0...])
                }
                x = concatenated(parts, axis: 1)
            }
        }
        x = x.squeezed(axis: 0)
        return proj2(gelu(proj1(lnPost(x))))
    }
}
