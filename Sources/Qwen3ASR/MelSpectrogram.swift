// Derived from soniqo/speech-swift Sources/Qwen3ASR/AudioPreprocessing.swift,
// commit cbcdfc6, Apache 2.0.
// Friday changes: the original zero-padded each 400-sample frame to a
// 512-point vDSP FFT and rebuilt the mel filterbank on 257 bins, which does not
// match the 400-point / 201-bin Whisper features the model was trained on, and it
// took the dynamic-range maximum before dropping the last frame. Rewritten to
// follow the Whisper/HF pipeline step by step on MLX (400-point rfft, slaney mel
// filters on 201 bins, trim last frame, then clamp to max-8, then (x+4)/4).
// Resampling was removed: callers must pass 16 kHz mono audio.

import Foundation
import MLX

public enum MelSpectrogram {
    public static let sampleRate = 16000
    public static let nFFT = 400
    public static let hopLength = 160
    public static let nMels = 128

    /// Slaney-style mel filterbank, shape [nMels, nFFT/2+1], identical in
    /// construction to librosa.filters.mel(sr=16000, n_fft=400, n_mels=128,
    /// htk=False, norm="slaney") (computed in Double, stored as Float).
    public static let filters: [Float] = {
        let nBins = nFFT / 2 + 1
        func hzToMel(_ hz: Double) -> Double {
            let fSp = 200.0 / 3.0, minLogHz = 1000.0
            let minLogMel = minLogHz / fSp, logstep = log(6.4) / 27.0
            return hz >= minLogHz ? minLogMel + log(hz / minLogHz) / logstep : hz / fSp
        }
        func melToHz(_ mel: Double) -> Double {
            let fSp = 200.0 / 3.0, minLogHz = 1000.0
            let minLogMel = minLogHz / fSp, logstep = log(6.4) / 27.0
            return mel >= minLogMel ? minLogHz * exp(logstep * (mel - minLogMel)) : fSp * mel
        }
        let fMax = Double(sampleRate) / 2
        let fftFreqs = (0 ..< nBins).map { fMax * Double($0) / Double(nBins - 1) }
        let melMax = hzToMel(fMax)
        let melF = (0 ..< nMels + 2).map { melToHz(melMax * Double($0) / Double(nMels + 1)) }
        var out = [Float](repeating: 0, count: nMels * nBins)
        for m in 0 ..< nMels {
            let enorm = 2.0 / (melF[m + 2] - melF[m])
            for k in 0 ..< nBins {
                let lower = (fftFreqs[k] - melF[m]) / (melF[m + 1] - melF[m])
                let upper = (melF[m + 2] - fftFreqs[k]) / (melF[m + 2] - melF[m + 1])
                out[m * nBins + k] = Float(max(0, min(lower, upper)) * enorm)
            }
        }
        return out
    }()

    /// Log-mel features for 16 kHz mono float audio. Returns [nMels, frames]
    /// float32 with frames = audio.count / hopLength.
    public static func compute(_ audio: [Float]) throws -> MLXArray {
        let pad = nFFT / 2
        guard audio.count > pad else {
            throw Qwen3ASRError.badAudio("audio too short: \(audio.count) samples")
        }
        // Reflect padding, as np.pad(mode="reflect"): [c b a b c d c b] for pad 2.
        var padded = [Float](repeating: 0, count: audio.count + 2 * pad)
        for i in 0 ..< pad { padded[i] = audio[pad - i] }
        for i in 0 ..< audio.count { padded[pad + i] = audio[i] }
        for i in 0 ..< pad { padded[pad + audio.count + i] = audio[audio.count - 2 - i] }

        let x = MLXArray(padded)
        let nFrames = 1 + (padded.count - nFFT) / hopLength
        let frames = asStrided(x, [nFrames, nFFT], strides: [hopLength, 1])
        let window = MLXArray((0 ..< nFFT).map {
            Float(0.5 - 0.5 * cos(2.0 * Double.pi * Double($0) / Double(nFFT)))
        })
        let spec = rfft(frames * window, axis: -1)
        let magnitudes = square(abs(spec))  // [nFrames, 201]
        let fb = MLXArray(filters, [nMels, nFFT / 2 + 1])
        let mel = matmul(fb, magnitudes.T)  // [nMels, nFrames]
        guard nFrames > 1 else {
            throw Qwen3ASRError.badAudio("audio too short for one mel frame")
        }
        var logSpec = log10(maximum(mel, MLXArray(Float(1e-10))))[0..., 0 ..< (nFrames - 1)]
        logSpec = maximum(logSpec, logSpec.max() - 8.0)
        return (logSpec + 4.0) / 4.0
    }
}
