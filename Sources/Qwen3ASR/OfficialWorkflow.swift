// Translated from Alibaba qwen-asr 0.0.6 (Qwen team, Apache 2.0),
// qwen_asr/inference/utils.py: split_audio_into_chunks (with
// MAX_ASR_INPUT_SECONDS = 1200, MIN_ASR_INPUT_SECONDS = 0.5),
// detect_and_fix_repetitions and parse_asr_output. speech-swift has no
// equivalent. The repetition fix is identical in mlx-qwen3-asr 0.4.4.

import Foundation

enum OfficialChunker {
    /// Chunks of at most `maxChunkSec`, cut at the quietest sample near each
    /// target boundary; concatenating them reproduces the input, except that
    /// chunks shorter than 0.5 s are padded with trailing silence.
    static func split(_ wav: [Float], sr: Int = 16000, maxChunkSec: Double = 1200,
                      searchExpandSec: Double = 5, minWindowMs: Double = 100) -> [[Float]] {
        let total = wav.count
        var chunks: [[Float]] = []
        if Double(total) / Double(sr) <= maxChunkSec {
            chunks = [wav]
        } else {
            let maxLen = Int(maxChunkSec * Double(sr))
            let expand = Int(searchExpandSec * Double(sr))
            let win = max(4, Int(minWindowMs / 1000 * Double(sr)))
            var start = 0
            while total - start > maxLen {
                let cut = start + maxLen
                let left = max(start, cut - expand), right = min(total, cut + expand)
                var boundary = cut
                if right - left > win {
                    // Lowest-energy window of `win` samples, then its quietest sample.
                    var sum: Float = 0
                    for i in left ..< left + win { sum += abs(wav[i]) }
                    var best = sum, bestPos = 0
                    for p in stride(from: 1, through: right - left - win, by: 1) {
                        sum += abs(wav[left + p + win - 1]) - abs(wav[left + p - 1])
                        if sum < best { best = sum; bestPos = p }
                    }
                    var inner = 0
                    for i in 0 ..< win where abs(wav[left + bestPos + i]) < abs(wav[left + bestPos + inner]) {
                        inner = i
                    }
                    boundary = left + bestPos + inner
                }
                boundary = min(max(boundary, start + 1), total)
                chunks.append(Array(wav[start ..< boundary]))
                start = boundary
            }
            chunks.append(Array(wav[start...]))
        }
        let minLen = Int(0.5 * Double(sr))
        return chunks.map { $0.count < minLen ? $0 + [Float](repeating: 0, count: minLen - $0.count) : $0 }
    }
}

enum OutputParser {
    /// Returns (language, transcript). With a forced language the whole output is
    /// the transcript. Without one the model writes "language X<asr_text>text";
    /// "language None" with no text means silence.
    static func parse(_ raw: String, forcedLanguage: String?) -> (String?, String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return ("", "") }
        s = fixRepetitions(s)
        if let forcedLanguage { return (forcedLanguage, s) }
        guard let r = s.range(of: "<asr_text>") else { return ("", s) }
        let meta = s[..<r.lowerBound]
        let text = String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if meta.lowercased().contains("language none") { return ("", text) }
        var lang = ""
        for line in meta.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { continue }
            if l.lowercased().hasPrefix("language ") {
                lang = String(l.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return (lang, text)
    }

    /// Collapse a code point repeated more than 20 times, then any 1-20 code point
    /// pattern repeated 20+ times, keeping one copy (on Unicode scalars, like
    /// Python str indexing).
    static func fixRepetitions(_ text: String, threshold: Int = 20) -> String {
        let chars = Array(text.unicodeScalars)
        var runFixed: [Unicode.Scalar] = []
        var i = 0
        while i < chars.count {
            var j = i + 1
            while j < chars.count, chars[j] == chars[i] { j += 1 }
            if j - i > threshold { runFixed.append(chars[i]) } else { runFixed += chars[i ..< j] }
            i = j
        }
        let fixed = fixPatternRuns(runFixed, threshold: threshold, maxPatternLen: 20)
        return String(String.UnicodeScalarView(fixed))
    }

    private static func fixPatternRuns(_ s: [Unicode.Scalar], threshold: Int, maxPatternLen: Int)
        -> [Unicode.Scalar]
    {
        let n = s.count
        if n < threshold * 2 { return s }
        var out: [Unicode.Scalar] = []
        var i = 0
        while i <= n - threshold * 2 {
            for k in 1 ... maxPatternLen {
                if i + k * threshold > n { break }
                let p = s[i ..< i + k]
                var ok = true
                for rep in 1 ..< threshold {
                    let st = i + rep * k
                    if st + k > n || s[st ..< st + k] != p { ok = false; break }
                }
                if !ok { continue }
                var end = i + threshold * k
                while end + k <= n, s[end ..< end + k] == p { end += k }
                out += p
                out += fixPatternRuns(Array(s[end...]), threshold: threshold, maxPatternLen: maxPatternLen)
                return out
            }
            out.append(s[i])
            i += 1
        }
        if i < n { out += s[i...] }
        return out
    }
}
