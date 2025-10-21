//
//  TextSegmentation.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import NaturalLanguage

@MainActor
extension GlobalAudioManager {

    // MARK: - Text Segmentation (unchanged behavior, optimized impl)
    func splitTextIntoMeaningfulSegments(_ rawText: String) -> [String] {
        let targetMinSec: Double = 5.0
        let targetMaxSec: Double = 10.0
        let enWordsPerSec: Double = 2.8
        let zhCharsPerSec: Double = 4.5
        let maxCJKLen = 75
        let maxWordLen = 50

        let normalized = normalizeLinesAddingPause(rawText)

        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = normalized

        var sentences: [String] = []
        sentenceTokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let s = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        if sentences.isEmpty {
            sentences = [normalized.trimmingCharacters(in: .whitespacesAndNewlines)]
                .compactMap { $0.isEmpty ? nil : $0 }
        }

        var i = 0
        var segments: [String] = []

        while i < sentences.count {
            let s1 = sentences[i]
            let lang1 = dominantLanguageCached(s1)
            let sec1 = estSeconds(s1, lang: lang1, enWPS: enWordsPerSec, zhCPS: zhCharsPerSec)
            let c1 = countFor(s1, lang: lang1)

            if sec1 > targetMaxSec || c1 > hardMax(for: lang1, maxWordLen: maxWordLen, maxCJKLen: maxCJKLen) {
                let pieces = splitOverlongSentence(
                    s1,
                    lang: lang1,
                    maxLen: hardMax(for: lang1, maxWordLen: maxWordLen, maxCJKLen: maxCJKLen),
                    targetMinSec: targetMinSec,
                    targetMaxSec: targetMaxSec,
                    enWPS: enWordsPerSec,
                    zhCPS: zhCharsPerSec
                )
                for p in pieces {
                    let pl = dominantLanguageCached(p)
                    segments.append(ensureTerminalPunctuation(p, lang: pl))
                }
                i += 1
                continue
            }

            if sec1 >= targetMinSec && sec1 <= targetMaxSec {
                segments.append(ensureTerminalPunctuation(s1, lang: lang1))
                i += 1
                continue
            }

            if sec1 < targetMinSec, i + 1 < sentences.count {
                let s2 = sentences[i + 1]
                let merged = (s1 + " " + s2).replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
                let mLang = dominantLanguageCached(merged)
                let mSec = estSeconds(merged, lang: mLang, enWPS: enWordsPerSec, zhCPS: zhCharsPerSec)
                let mCount = countFor(merged, lang: mLang)
                if mSec <= targetMaxSec &&
                    mCount <= hardMax(for: mLang, maxWordLen: maxWordLen, maxCJKLen: maxCJKLen) {
                    segments.append(ensureTerminalPunctuation(merged, lang: mLang))
                    i += 2
                    continue
                } else {
                    segments.append(ensureTerminalPunctuation(s1, lang: lang1))
                    i += 1
                    continue
                }
            }

            segments.append(ensureTerminalPunctuation(s1, lang: lang1))
            i += 1
        }

        let cleaned = segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return cleaned
    }

    // MARK: - Normalization (single pass, no regex loops)
    func normalizeLinesAddingPause(_ text: String) -> String {
        var base = text
        base = base.replacingOccurrences(of: #"[ \t\u{00A0}]{2,}"#, with: " ", options: .regularExpression)
        let lines = base.split(whereSeparator: \.isNewline).map { String($0) }

        if lines.isEmpty { return text.trimmingCharacters(in: .whitespacesAndNewlines) }

        var out = lines[0]
        for idx in 1..<lines.count {
            let trimmedOut = out.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastScalar = trimmedOut.unicodeScalars.last
            let lastChar = lastScalar.map { Character($0) }

            let terminals: Set<Character> = ["。","！","？",".","!","?","…","；",";","．"]
            let commaLikes: Set<Character> = ["，",",","、",":","：","；",";"]

            let needPause: Bool
            if let lc = lastChar {
                needPause = !(terminals.contains(lc) || commaLikes.contains(lc))
            } else {
                needPause = true
            }

            if needPause {
                let comma = isCJKChar(lastScalar) ? "，" : ","
                out += comma
            }
            out += "\n" + lines[idx]
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Language & counting helpers (cached)
    func dominantLanguageCached(_ text: String) -> String {
        let key = text as NSString
        if let v = langCache.object(forKey: key) { return v as String }
        let r = NLLanguageRecognizer()
        r.processString(text)
        let lang = (r.dominantLanguage?.rawValue) ?? "und"
        langCache.setObject(lang as NSString, forKey: key)
        return lang
    }

    func isWordLanguage(_ lang: String) -> Bool {
        return !["ja","ko","zh-Hans","zh-Hant","zh"].contains(lang)
    }

    func wordCountCached(_ text: String) -> Int {
        let key = text as NSString
        if let v = wordCountCache.object(forKey: key) { return v.intValue }
        let t = NLTokenizer(unit: .word)
        t.string = text
        var c = 0
        t.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in c += 1; return true }
        wordCountCache.setObject(NSNumber(value: c), forKey: key)
        return c
    }

    func countFor(_ text: String, lang: String) -> Int {
        isWordLanguage(lang) ? wordCountCached(text) : text.count
    }

    func estSeconds(_ text: String, lang: String, enWPS: Double, zhCPS: Double) -> Double {
        if isWordLanguage(lang) {
            return Double(wordCountCached(text)) / enWPS
        } else {
            return Double(text.count) / zhCPS
        }
    }

    func hardMax(for lang: String, maxWordLen: Int, maxCJKLen: Int) -> Int {
        isWordLanguage(lang) ? maxWordLen : maxCJKLen
    }

    func ensureTerminalPunctuation(_ text: String, lang: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.unicodeScalars.last else { return trimmed }
        let lastCh = Character(last)
        let terminal: Set<Character> = ["。","！","？",".","!","?","…","；",";","．"]
        if terminal.contains(lastCh) { return trimmed }
        let commaLike: Set<Character> = ["，",",","、",":","：","；",";"]
        if commaLike.contains(lastCh) {
            return trimmed + (isWordLanguage(lang) ? "." : "。")
        }
        return trimmed + (isWordLanguage(lang) ? "." : "。")
    }

    func isCJKChar(_ scalarOpt: UnicodeScalar?) -> Bool {
        guard let s = scalarOpt else { return false }
        switch s.value {
        case 0x4E00...0x9FFF,
             0x3400...0x4DBF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF,
             0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    func splitOverlongSentence(_ sentence: String,
                               lang: String,
                               maxLen: Int,
                               targetMinSec: Double,
                               targetMaxSec: Double,
                               enWPS: Double,
                               zhCPS: Double) -> [String] {
        let midPunctPattern = #"[,，、;；:：]"#
        var parts = sentence.split(usingRegex: midPunctPattern)
        if parts.isEmpty { parts = [sentence] }

        var reduced: [String] = []
        var buffer = ""

        func secs(_ s: String, _ l: String) -> Double {
            isWordLanguage(l) ? Double(wordCountCached(s)) / enWPS : Double(s.count) / zhCPS
        }

        for p in parts {
            let candidate = buffer.isEmpty ? p : (buffer + " " + p)
            let l = dominantLanguageCached(candidate)
            let c = countFor(candidate, lang: l)
            if c <= maxLen && secs(candidate, l) <= max(targetMaxSec * 1.15, targetMaxSec) {
                buffer = candidate
            } else {
                if !buffer.isEmpty { reduced.append(buffer) }
                buffer = p
            }
        }
        if !buffer.isEmpty { reduced.append(buffer) }

        var finalPieces: [String] = []
        for piece in reduced {
            let l = dominantLanguageCached(piece)
            let needForce =
                (!isWordLanguage(l) && piece.count > maxLen) ||
                (isWordLanguage(l) && wordCountCached(piece) > maxLen) ||
                secs(piece, l) > targetMaxSec

            if needForce {
                finalPieces.append(contentsOf:
                    forceSplitByWordBoundary(piece, lang: l, maxLen: maxLen)
                )
            } else {
                finalPieces.append(piece)
            }
        }
        return finalPieces
    }

    /// Uses `NLTokenizer(.word)` to enforce word boundary splits.
    func forceSplitByWordBoundary(_ text: String, lang: String, maxLen: Int) -> [String] {
        var pieces: [String] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var current = ""
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            let candidate = current.isEmpty ? token : (current + (needsSpaceBetween(current, token) ? " " : "") + token)

            let currentLen: Int = isWordLanguage(lang) ? wordCountCached(candidate) : candidate.count
            if currentLen > maxLen {
                if !current.isEmpty { pieces.append(current) }
                current = token
            } else {
                current = candidate
            }
            return true
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    func needsSpaceBetween(_ a: String, _ b: String) -> Bool {
        let aLast = a.unicodeScalars.last
        let bFirst = b.unicodeScalars.first
        let aCJK = isCJKChar(aLast)
        let bCJK = isCJKChar(bFirst)
        if aCJK || bCJK { return false }
        return true
    }
}
