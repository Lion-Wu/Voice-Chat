//
//  SpeechTranscriptMerger.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

enum SpeechTranscriptMerger {
    static func merge(_ prefix: String, _ suffix: String) -> String {
        let left = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }

        guard let last = left.unicodeScalars.last, let first = right.unicodeScalars.first else {
            return left + right
        }

        let needsSpace = isASCIIAlphaNumeric(first)
            && (isASCIIAlphaNumeric(last) || isASCIISentencePunctuation(last) || isCJK(last))
        return needsSpace ? "\(left) \(right)" : (left + right)
    }

    private static func isASCIIAlphaNumeric(_ scalar: UnicodeScalar) -> Bool {
        scalar.isASCII && (scalar.properties.isAlphabetic || scalar.properties.numericType != nil)
    }

    private static func isASCIISentencePunctuation(_ scalar: UnicodeScalar) -> Bool {
        scalar.isASCII && ".?!:;".unicodeScalars.contains(scalar)
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF: return true
        case 0x3400...0x4DBF: return true
        case 0x4E00...0x9FFF: return true
        case 0xAC00...0xD7AF: return true
        default: return false
        }
    }
}
