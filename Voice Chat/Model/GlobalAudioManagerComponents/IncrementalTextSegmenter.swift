//
//  IncrementalTextSegmenter.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

/// Accumulates streamed text into speakable segments:
/// - Ignore content inside <think>…</think> blocks and only emit visible body text.
/// - Split on sentence-ending punctuation (English and CJK) or line breaks.
/// - If punctuation never arrives, enforce a length-based split to keep audio flowing.
struct IncrementalTextSegmenter {

    private var buffer: String = ""
    private var inThink: Bool = false

    // Empirical thresholds: approximate words for English and characters for CJK languages.
    private let maxCJKChars: Int = 80
    private let maxENWords: Int = 30

    // Sentence-ending punctuation.
    private let terminalSet: Set<Character> = Set("。！？!?……;；.。")
    // Soft line break (treat newline as a split point).
    private let newline: Character = "\n"

    mutating func reset() {
        buffer = ""
        inThink = false
    }

    /// Append a streamed delta and return any segments ready for narration.
    mutating func append(_ delta: String) -> [String] {
        guard !delta.isEmpty else { return [] }

        var produced: [String] = []
        var i = delta.startIndex

        while i < delta.endIndex {
            // Track when we enter or exit a <think> block.
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

            // Only append non-think content to the buffer.
            let ch = delta[i]
            if !inThink {
                buffer.append(ch)

                // Split immediately on newline or terminal punctuation.
                if ch == newline || terminalSet.contains(ch) {
                    let seg = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seg.isEmpty {
                        produced.append(seg)
                    }
                    buffer = ""
                } else {
                    // Force a split when the buffer grows too long without punctuation.
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

    /// Finalize the stream by flushing the remaining buffered text.
    mutating func finalize() -> [String] {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return [tail]
    }

    // MARK: - Helpers

    /// Lightweight word/character counting heuristic for forced splits.
    private func shouldForceSplit(_ text: String) -> Bool {
        // Check whether the buffer contains CJK characters.
        let hasCJK = text.unicodeScalars.contains { $0.properties.isIdeographic }
        if hasCJK {
            return text.count >= maxCJKChars
        } else {
            let words = text.split { $0.isWhitespace || $0.isNewline }
            return words.count >= maxENWords
        }
    }
}
