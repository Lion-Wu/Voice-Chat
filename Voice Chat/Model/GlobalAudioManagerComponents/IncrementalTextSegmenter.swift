//
//  IncrementalTextSegmenter.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

/// Builds readable segments from streaming text increments.
/// - Ignores content inside `<think>` blocks and only emits body text.
/// - Splits on sentence punctuation (English/Chinese) or line breaks.
/// - Falls back to length-based splits when punctuation is missing to avoid long delays.
struct IncrementalTextSegmenter {

    private var buffer: String = ""
    private var inThink: Bool = false

    // Heuristic thresholds: word counts for English, character counts for CJK.
    private let maxCJKChars: Int = 80
    private let maxENWords: Int = 30

    // Sentence-ending punctuation
    private let terminalSet: Set<Character> = Set("。！？!?……;；.。")
    // Soft line breaks (including newline)
    private let newline: Character = "\n"

    mutating func reset() {
        buffer = ""
        inThink = false
    }

    /// Appends streamed text and returns newly available segments.
    mutating func append(_ delta: String) -> [String] {
        guard !delta.isEmpty else { return [] }

        var produced: [String] = []
        var i = delta.startIndex

        while i < delta.endIndex {
            // Track entering and exiting `<think>` blocks
            if delta[i...].hasPrefix("<think>") {
                inThink = true
                i = delta.index(i, offsetBy: 7)
                continue
            }
            if delta[i...].hasPrefix("</think>") {
                inThink = false
                i = delta.index(i, offsetBy: 8)
                continue
            }

            // Only buffer non-`<think>` content
            let ch = delta[i]
            if !inThink {
                buffer.append(ch)

                // Split immediately on newline or sentence punctuation
                if ch == newline || terminalSet.contains(ch) {
                    let seg = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seg.isEmpty {
                        produced.append(seg)
                    }
                    buffer = ""
                } else {
                    // Force a split when exceeding the fallback length threshold
                    if shouldForceSplit(buffer) {
                        let seg = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !seg.isEmpty {
                            produced.append(seg)
                        }
                        buffer = ""
                    }
                }
            }

            i = delta.index(after: i)
        }

        return produced
    }

    /// Flushes remaining buffered text once the stream ends.
    mutating func finalize() -> [String] {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return [tail]
    }

    // MARK: - Helpers

    /// Simple fallback based on English word and Chinese character counts.
    private func shouldForceSplit(_ text: String) -> Bool {
        // Determine whether the string contains CJK characters
        let hasCJK = text.unicodeScalars.contains { $0.properties.isIdeographic }
        if hasCJK {
            return text.count >= maxCJKChars
        } else {
            let words = text.split { $0.isWhitespace || $0.isNewline }
            return words.count >= maxENWords
        }
    }
}
