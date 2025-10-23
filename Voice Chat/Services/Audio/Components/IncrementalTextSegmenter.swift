//
//  IncrementalTextSegmenter.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

/// Collects streamed text into playable segments.
/// - Skips content inside <think> tags and emits only the main body.
/// - Splits on sentence terminators (. ! ? and their CJK variants) or new lines.
/// - Forces a split when no punctuation appears after a configurable length.
struct IncrementalTextSegmenter {

    private var buffer: String = ""
    private var inThink: Bool = false

    // Heuristic thresholds: count English words or CJK characters.
    private let maxCJKChars: Int = 80
    private let maxENWords: Int = 30

    // Sentence terminators.
    private let terminalSet: Set<Character> = Set("。！？!?……;；.。")
    // Soft break character (treat newline as a separator).
    private let newline: Character = "\n"

    mutating func reset() {
        buffer = ""
        inThink = false
    }

    /// Appends a delta and returns any segments ready for playback.
    mutating func append(_ delta: String) -> [String] {
        guard !delta.isEmpty else { return [] }

        var produced: [String] = []
        var i = delta.startIndex

        while i < delta.endIndex {
            // Handle entering and leaving <think> sections.
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

            // Only keep content outside <think> blocks.
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

    /// Emits any remaining text when the stream ends.
    mutating func finalize() -> [String] {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return [tail]
    }

    // MARK: - Helpers

    /// Determines whether a forced split is required based on length heuristics.
    private func shouldForceSplit(_ text: String) -> Bool {
        // Check for CJK content to determine which threshold to use.
        let hasCJK = text.unicodeScalars.contains { $0.properties.isIdeographic }
        if hasCJK {
            return text.count >= maxCJKChars
        } else {
            let words = text.split { $0.isWhitespace || $0.isNewline }
            return words.count >= maxENWords
        }
    }
}
