//
//  IncrementalTextSegmenter.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

/// Build incremental streaming text into readable segments.
/// - Ignore content inside <think>…</think> blocks and emit only visible text.
/// - Split on sentence punctuation or line breaks.
/// - If no punctuation arrives for a long time, split by length to avoid long delays.
struct IncrementalTextSegmenter {

    private var buffer: String = ""
    private var inThink: Bool = false

    // Heuristics for enforced splits: words for English, characters for CJK.
    private let maxCJKChars: Int = 80
    private let maxENWords: Int = 30

    // Sentence punctuation marks.
    private let terminalSet: Set<Character> = Set("。！？!?……;；.。")
    // Soft line breaks also count as boundaries.
    private let newline: Character = "\n"

    mutating func reset() {
        buffer = ""
        inThink = false
    }

    /// Append an incremental chunk and return any ready-to-read segments.
    mutating func append(_ delta: String) -> [String] {
        guard !delta.isEmpty else { return [] }

        var produced: [String] = []
        var i = delta.startIndex

        while i < delta.endIndex {
            // Track entry and exit of <think> blocks.
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

            // Only append visible content.
            let ch = delta[i]
            if !inThink {
                buffer.append(ch)

                // Split immediately on punctuation or newline.
                if ch == newline || terminalSet.contains(ch) {
                    let seg = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seg.isEmpty {
                        produced.append(seg)
                    }
                    buffer = ""
                } else {
                    // Enforce a split when content grows too long without punctuation.
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

    /// Finish the stream and emit any remaining buffer.
    mutating func finalize() -> [String] {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return [tail]
    }

    // MARK: - Helpers

    /// Lightweight helper to decide length-based splits.
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
