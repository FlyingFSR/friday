// Derived from soniqo/speech-swift Sources/AudioCommon/Tokenizer.swift, commit
// cbcdfc6, Apache 2.0.
// Friday changes: the original pre-tokenized only on whitespace (no Qwen2
// regex: digits, punctuation and letters were not split the official way) and
// silently dropped pieces missing from the vocabulary, so hot-word context was
// encoded differently from the official tokenizer. This version follows the
// byte-level BPE of Qwen2 / mlx-qwen3-asr: added tokens are matched first
// (longest first), the rest is split with the Qwen2 pre-tokenizer regex, each
// piece is byte-mapped and BPE-merged by rank, unknown pieces map to the unk id.
// Decoding skips added tokens marked special (as the official decode with
// skip_special_tokens=True does) and replaces invalid UTF-8.

import Foundation

public final class Qwen3Tokenizer {
    private var encoder: [String: Int] = [:]
    private var decoder: [Int: String] = [:]
    private var addedEncoder: [String: Int] = [:]
    private var addedDecoder: [Int: String] = [:]
    private var specialIds: Set<Int> = []
    private var addedSorted: [String] = []
    private var bpeRanks: [String: Int] = [:]  // "a b" -> rank
    private var bpeCache: [String: [String]] = [:]
    private let unkId: Int
    private let pretokenize: NSRegularExpression

    static let pretokenizePattern =
        #"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#

    static let byteEncoder: [UInt8: Character] = {
        var bs: [Int] = Array(33 ... 126) + Array(161 ... 172) + Array(174 ... 255)
        var cs = bs
        var n = 0
        for b in 0 ..< 256 where !bs.contains(b) {
            bs.append(b)
            cs.append(256 + n)
            n += 1
        }
        var m: [UInt8: Character] = [:]
        for (b, c) in zip(bs, cs) { m[UInt8(b)] = Character(UnicodeScalar(c)!) }
        return m
    }()

    static let byteDecoder: [Character: UInt8] = {
        Dictionary(uniqueKeysWithValues: byteEncoder.map { ($1, $0) })
    }()

    public init(directory: URL) throws {
        guard let vocab = try JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent("vocab.json"))) as? [String: Int]
        else { throw Qwen3ASRError.badTokenizer("vocab.json is not {token: id}") }
        encoder = vocab
        for (t, i) in vocab { decoder[i] = t }

        let merges = try String(contentsOf: directory.appendingPathComponent("merges.txt"), encoding: .utf8)
        for (i, raw) in merges.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            bpeRanks["\(parts[0]) \(parts[1])"] = i
        }
        guard !bpeRanks.isEmpty else { throw Qwen3ASRError.badTokenizer("merges.txt is empty") }

        let cfg = try readJSON(directory.appendingPathComponent("tokenizer_config.json"))
        if let added = cfg["added_tokens_decoder"] as? [String: [String: Any]] {
            for (idStr, meta) in added {
                guard let id = Int(idStr), let content = meta["content"] as? String, !content.isEmpty
                else { continue }
                addedEncoder[content] = id
                addedDecoder[id] = content
                if (meta["special"] as? Bool) == true { specialIds.insert(id) }
            }
        }
        addedSorted = addedEncoder.keys.sorted { $0.count > $1.count }
        let eos = (cfg["eos_token"] as? String) ?? "<|endoftext|>"
        let unk = (cfg["unk_token"] as? String) ?? eos
        unkId = addedEncoder[unk] ?? encoder[unk] ?? 151643
        pretokenize = try NSRegularExpression(pattern: Self.pretokenizePattern)
    }

    public func tokenId(_ token: String) -> Int? { addedEncoder[token] ?? encoder[token] }

    public func encode(_ text: String) -> [Int] {
        var ids: [Int] = []
        for (isAdded, segment) in splitAddedTokens(text) {
            if isAdded {
                if let id = addedEncoder[segment] { ids.append(id) }
                continue
            }
            let ns = segment as NSString
            for m in pretokenize.matches(in: segment, range: NSRange(location: 0, length: ns.length)) {
                let piece = ns.substring(with: m.range)
                let mapped = String(piece.utf8.map { Self.byteEncoder[$0]! })
                for t in bpe(mapped) { ids.append(encoder[t] ?? unkId) }
            }
        }
        return ids
    }

    public func decode(_ ids: [Int], skipSpecial: Bool = true) -> String {
        var out = ""
        var bytes: [UInt8] = []
        func flush() {
            if !bytes.isEmpty { out += String(decoding: bytes, as: UTF8.self); bytes.removeAll() }
        }
        for id in ids {
            if let added = addedDecoder[id] {
                if skipSpecial, specialIds.contains(id) { continue }
                flush()
                out += added
                continue
            }
            guard let tok = decoder[id] else { continue }
            for ch in tok { if let b = Self.byteDecoder[ch] { bytes.append(b) } }
        }
        flush()
        return out
    }

    private func splitAddedTokens(_ text: String) -> [(Bool, String)] {
        var parts: [(Bool, String)] = []
        var buffer = ""
        var rest = Substring(text)
        outer: while !rest.isEmpty {
            for t in addedSorted where rest.hasPrefix(t) {
                if !buffer.isEmpty { parts.append((false, buffer)); buffer = "" }
                parts.append((true, t))
                rest = rest.dropFirst(t.count)
                continue outer
            }
            buffer.append(rest.removeFirst())
        }
        if !buffer.isEmpty { parts.append((false, buffer)) }
        return parts
    }

    private func bpe(_ token: String) -> [String] {
        if let cached = bpeCache[token] { return cached }
        var word = token.map { String($0) }
        if word.count < 2 { return word }
        while word.count > 1 {
            var best: (Int, String, String)?
            for i in 0 ..< word.count - 1 {
                if let r = bpeRanks["\(word[i]) \(word[i + 1])"], r < (best?.0 ?? Int.max) {
                    best = (r, word[i], word[i + 1])
                }
            }
            guard let (_, first, second) = best else { break }
            var merged: [String] = []
            var i = 0
            while i < word.count {
                if i < word.count - 1, word[i] == first, word[i + 1] == second {
                    merged.append(first + second)
                    i += 2
                } else {
                    merged.append(word[i])
                    i += 1
                }
            }
            word = merged
        }
        bpeCache[token] = word
        return word
    }
}
