//
//  IncrementalTextSegmenter.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

/// Groups streaming text into speakable segments:
/// - ignores anything wrapped in `<think>...</think>`;
/// - splits on sentence terminators (e.g. `. ! ?` and the Chinese variants) or newlines;
/// - enforces a split when no punctuation appears after a length threshold.
struct IncrementalTextSegmenter {

    private var buffer: String = ""
    private var inThink: Bool = false
    private var lastCharacter: Character?

    private let openMarker = "<think>"
    private let closeMarker = "</think>"

    // Heuristics: measure English by word count and CJK text by character count.
    private let maxCJKChars: Int = 80
    private let maxENWords: Int = 30

    // Sentence-ending punctuation to watch for.
    private let terminalSet: Set<Character> = Set("。！？!?……;；.。")
    // Treat newline as a soft break as well.
    private let newline: Character = "\n"

    mutating func reset() {
        buffer = ""
        inThink = false
        lastCharacter = nil
    }

    /// Appends a streaming delta and returns any completed, speakable segments.
    mutating func append(_ delta: String) -> [String] {
        guard !delta.isEmpty else { return [] }

        var produced: [String] = []
        var i = delta.startIndex

        while i < delta.endIndex {
            // Handle entering and exiting `<think>` blocks.
            if isStandaloneMarker(delta, at: i, marker: openMarker) {
                inThink = true
                lastCharacter = delta[delta.index(i, offsetBy: openMarker.count - 1)]
                i = delta.index(i, offsetBy: openMarker.count)
                continue
            }
            if isStandaloneMarker(delta, at: i, marker: closeMarker) {
                inThink = false
                lastCharacter = delta[delta.index(i, offsetBy: closeMarker.count - 1)]
                i = delta.index(i, offsetBy: closeMarker.count)
                continue
            }

            // Only buffer content outside of `<think>` blocks.
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
                    // Force a split if the segment grows too long without punctuation.
                    if shouldForceSplit(buffer) {
                        let seg = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !seg.isEmpty {
                            produced.append(seg)
                        }
                        buffer = ""
                    }
                }
            }

            lastCharacter = ch
            i = delta.index(after: i)
        }

        return produced
    }

    /// Flushes any remaining buffer when the stream ends.
    mutating func finalize() -> [String] {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return [tail]
    }

    // MARK: - Helpers

    /// Checks whether a marker token appears alone on a line (aside from surrounding whitespace).
    private func isStandaloneMarker(_ delta: String, at index: String.Index, marker: String) -> Bool {
        guard delta[index...].hasPrefix(marker) else { return false }

        let beforeChar: Character?
        if index == delta.startIndex {
            beforeChar = lastCharacter
        } else {
            beforeChar = delta[delta.index(before: index)]
        }
        let beforeIsLineBoundary = beforeChar == nil || beforeChar?.isNewline == true
        guard beforeIsLineBoundary else { return false }

        let afterIndex = delta.index(index, offsetBy: marker.count)
        if afterIndex == delta.endIndex { return true }
        return delta[afterIndex].isNewline
    }

    /// Simple heuristic to decide when to force a split for English or CJK text.
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
