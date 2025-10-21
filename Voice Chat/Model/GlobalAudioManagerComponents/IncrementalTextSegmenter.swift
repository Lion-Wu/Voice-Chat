//
//  IncrementalTextSegmenter.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

/// Builds readable segments from streamed text:
/// - Ignores content inside <think>…</think> blocks and only emits body text.
/// - Splits on sentence-ending punctuation or line breaks.
/// - If punctuation is absent for a long time, applies a length threshold to force a split.
struct IncrementalTextSegmenter {

    private var buffer: String = ""
    private var inThink: Bool = false

    // Length thresholds (approximate words for English, characters for Chinese).
    private let maxCJKChars: Int = 80
    private let maxENWords: Int = 30

    // Sentence-ending punctuation.
    private let terminalSet: Set<Character> = Set("。！？!?……;；.。")
    // Soft line breaks (including newline characters).
    private let newline: Character = "\n"

    mutating func reset() {
        buffer = ""
        inThink = false
    }

    /// Appends a new delta and returns segments ready for playback.
    mutating func append(_ delta: String) -> [String] {
        guard !delta.isEmpty else { return [] }

        var produced: [String] = []
        var i = delta.startIndex

        while i < delta.endIndex {
            // Track opening and closing of think tags.
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

                // Split immediately on line breaks or sentence-ending punctuation.
                if ch == newline || terminalSet.contains(ch) {
                    let seg = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seg.isEmpty {
                        produced.append(seg)
                    }
                    buffer = ""
                } else {
                    // Force split when no punctuation is found within the threshold.
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

    /// Emits any trailing content when the stream finishes.
    mutating func finalize() -> [String] {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return [tail]
    }

    // MARK: - Helpers

    /// Simple word/character counting to enforce length-based splits.
    private func shouldForceSplit(_ text: String) -> Bool {
        // Detect whether the text contains CJK characters.
        let hasCJK = text.unicodeScalars.contains { $0.properties.isIdeographic }
        if hasCJK {
            return text.count >= maxCJKChars
        } else {
            let words = text.split { $0.isWhitespace || $0.isNewline }
            return words.count >= maxENWords
        }
    }
}
