// Derived from soniqo/speech-swift Sources/Qwen3ASR/WeightLoading.swift and
// Sources/MLXCommon/WeightLoading.swift, commit cbcdfc6, Apache 2.0.
// Friday changes: the original applied tensors with Module.update(parameters:),
// which does not verify shapes, and silently left any missing tensor at its zero
// initial value (a wrong transcript instead of an error). This version builds each
// layer directly from the checkpoint, fails on any missing or mis-shaped tensor,
// and fails if the checkpoint contains tensors nobody used. It accepts both the
// official HF layout ("thinker." prefix, PyTorch conv layout) and the
// mlx-qwen3-asr layout (no prefix, MLX conv layout, used by Friday's download), and quantized or float
// linears in either the encoder or the decoder.

import Foundation
import MLX

/// A linear layer: either plain (weight [out, in]) or affine-quantized.
public struct LinearW {
    let weight: MLXArray
    let bias: MLXArray?
    let scales: MLXArray?
    let biases: MLXArray?
    let groupSize: Int
    let bits: Int

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var y: MLXArray
        if let scales {
            y = quantizedMM(x, weight, scales: scales, biases: biases, transpose: true,
                            groupSize: groupSize, bits: bits)
        } else {
            y = matmul(x, weight.T)
        }
        if let bias { y = y + bias }
        return y
    }
}

final class WeightStore {
    private var tensors: [String: MLXArray] = [:]
    private var used: Set<String> = []
    /// Every tensor handed to the model, so the loader can evaluate them in one go.
    private(set) var consumedArrays: [MLXArray] = []
    let quant: QuantizationConfig?
    let dtype: DType

    init(directory: URL, quant: QuantizationConfig?, dtype: DType) throws {
        self.quant = quant
        self.dtype = dtype
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw Qwen3ASRError.badWeights("no .safetensors in \(directory.path)") }
        for file in files {
            for (key, value) in try loadArrays(url: file) {
                var k = key
                var v = value
                if k.hasPrefix("thinker.") {
                    k = String(k.dropFirst("thinker.".count))
                    // Official checkpoint: PyTorch Conv2d [out, in, kH, kW] -> MLX [out, kH, kW, in].
                    if k.hasPrefix("audio_tower.conv2d"), k.hasSuffix(".weight"), v.ndim == 4 {
                        v = v.transposed(0, 2, 3, 1)
                    }
                }
                guard tensors[k] == nil else { throw Qwen3ASRError.badWeights("duplicate tensor \(k)") }
                tensors[k] = v
            }
        }
    }

    func has(_ key: String) -> Bool { tensors[key] != nil }

    /// Floating tensor, cast to the model dtype, with an exact shape check.
    func float(_ key: String, _ shape: [Int]) throws -> MLXArray {
        guard let t = tensors[key] else { throw Qwen3ASRError.badWeights("missing \(key)") }
        guard t.shape == shape else {
            throw Qwen3ASRError.badWeights("\(key): expected \(shape), got \(t.shape)")
        }
        used.insert(key)
        let out = t.dtype == dtype ? t : t.asType(dtype)
        consumedArrays.append(out)
        return out
    }

    func linear(_ path: String, inDim: Int, outDim: Int, bias: Bool) throws -> LinearW {
        let b = bias ? try float("\(path).bias", [outDim]) : nil
        if has("\(path).scales") {
            let (w, s, qb, gs, bits) = try quantized(path, rows: outDim, cols: inDim)
            return LinearW(weight: w, bias: b, scales: s, biases: qb, groupSize: gs, bits: bits)
        }
        let w = try float("\(path).weight", [outDim, inDim])
        return LinearW(weight: w, bias: b, scales: nil, biases: nil, groupSize: 0, bits: 0)
    }

    /// Packed affine-quantized matrix [rows, cols]: weight uint32 [rows, cols*bits/32],
    /// scales and biases [rows, cols/groupSize].
    func quantized(_ path: String, rows: Int, cols: Int) throws
        -> (MLXArray, MLXArray, MLXArray, Int, Int)
    {
        guard let quant else {
            throw Qwen3ASRError.badWeights("\(path) is quantized but quantization_config.json is missing")
        }
        let wKey = "\(path).weight"
        guard let w = tensors[wKey] else { throw Qwen3ASRError.badWeights("missing \(wKey)") }
        guard w.dtype == .uint32, w.shape == [rows, cols * quant.bits / 32] else {
            throw Qwen3ASRError.badWeights(
                "\(wKey): expected uint32 \([rows, cols * quant.bits / 32]) for \(quant.bits)-bit, got \(w.dtype) \(w.shape)")
        }
        used.insert(wKey)
        consumedArrays.append(w)
        let groups = cols / quant.groupSize
        let s = try float("\(path).scales", [rows, groups])
        let b = try float("\(path).biases", [rows, groups])
        return (w, s, b, quant.groupSize, quant.bits)
    }

    /// Throws if any checkpoint tensor was never consumed by the model.
    func checkAllUsed() throws {
        let unused = Set(tensors.keys).subtracting(used).sorted()
        guard unused.isEmpty else {
            throw Qwen3ASRError.badWeights("\(unused.count) unused tensors, e.g. \(unused.prefix(5))")
        }
    }

    /// Drop references so the loader does not keep a second copy alive.
    func release() { tensors.removeAll() }
}
