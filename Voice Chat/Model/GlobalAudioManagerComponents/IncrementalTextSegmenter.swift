//
//  IncrementalTextSegmenter.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import NaturalLanguage

/// Groups streaming text into speakable segments:
/// - ignores anything wrapped in `<think>...</think>`;
/// - in realtime voice mode, ramps segment length from short to normal so the first chunk arrives quickly;
/// - prefers punctuation boundaries, and falls back to NLTokenizer word boundaries when text grows too long.
struct IncrementalTextSegmenter {

    private struct SegmentRampProfile {
        let minSeconds: Double
        let preferredSeconds: Double
        let maxSeconds: Double
    }

    private struct SegmentThresholds {
        let minUnits: Int
        let preferredUnits: Int
        let maxUnits: Int
        let minSeconds: Double
        let preferredSeconds: Double
        let maxSeconds: Double
    }

    private enum UnitMode {
        case cjkCharacters
        case words
    }

    private var buffer: String = ""
    private var inThink: Bool = false
    private var lastCharacter: Character?
    // Number of already emitted segments in this realtime stream.
    private var emittedSegmentCount: Int = 0

    private let openMarker = "<think>"
    private let closeMarker = "</think>"

    // Heuristics: estimate speech time by word count (word languages) and character count (CJK).
    private let enWordsPerSecond: Double = 2.8
    private let cjkCharsPerSecond: Double = 4.5
    // For unspaced / punctuation-heavy non-CJK text, approximate "word units" by characters.
    private let approxCharsPerWordUnit: Double = 5.5
    // Cap normal segment length around 15 seconds.
    private let maxNormalSeconds: Double = 15.0

    // Realtime ramp strategy: short first chunk, then gradually increase to normal length.
    private let rampProfiles: [SegmentRampProfile] = [
        .init(minSeconds: 1.2, preferredSeconds: 2.6, maxSeconds: 4.2),
        .init(minSeconds: 2.5, preferredSeconds: 4.8, maxSeconds: 6.8),
        .init(minSeconds: 4.0, preferredSeconds: 7.2, maxSeconds: 9.8),
        .init(minSeconds: 5.6, preferredSeconds: 9.2, maxSeconds: 12.6),
        .init(minSeconds: 7.0, preferredSeconds: 11.2, maxSeconds: 15.0)
    ]

    // Sentence-ending punctuation to watch for.
    private let terminalSet: Set<Character> = Set("。！？!?…;；.")
    // We can also split on these punctuation marks when a forced split is needed.
    private let softPunctuationSet: Set<Character> = Set(",，、:：")
    // Treat newline as a soft break as well.
    private let newline: Character = "\n"

    mutating func reset() {
        buffer = ""
        inThink = false
        lastCharacter = nil
        emittedSegmentCount = 0
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

                if isTerminalBoundary(ch) {
                    // Prefer splitting at punctuation/newline when the current stage minimum is reached.
                    produced.append(contentsOf: drainBufferOnBoundary())
                } else if shouldForceSplit(buffer) {
                    // If text becomes too long, force a fluent split (prefer punctuation, then word boundary).
                    produced.append(contentsOf: drainBufferForcefully())
                }
            }

            lastCharacter = ch
            i = delta.index(after: i)
        }

        return produced
    }

    /// Flushes any remaining buffer when the stream ends.
    mutating func finalize() -> [String] {
        var produced: [String] = []

        while shouldForceSplit(buffer) {
            let next = splitOffNextSegment(force: true)
            guard let seg = next else { break }
            produced.append(seg)
        }

        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        if !tail.isEmpty {
            produced.append(tail)
            emittedSegmentCount += 1
        }
        return produced
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

    /// Decides whether the current buffer has exceeded the current segment's upper bound.
    private func shouldForceSplit(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let mode = unitMode(for: trimmed)
        let thresholds = thresholdsForCurrentStage(mode: mode)
        return unitCount(in: trimmed, mode: mode) >= thresholds.maxUnits ||
               estimatedSeconds(for: trimmed, mode: mode) >= thresholds.maxSeconds
    }

    private func isTerminalBoundary(_ ch: Character) -> Bool {
        ch == newline || terminalSet.contains(ch)
    }

    private func isPunctuationBoundary(_ ch: Character) -> Bool {
        isTerminalBoundary(ch) || softPunctuationSet.contains(ch)
    }

    private mutating func drainBufferOnBoundary() -> [String] {
        guard let segment = splitOffNextSegment(force: false) else { return [] }
        return [segment]
    }

    private mutating func drainBufferForcefully() -> [String] {
        var produced: [String] = []
        while shouldForceSplit(buffer) {
            guard let segment = splitOffNextSegment(force: true) else { break }
            produced.append(segment)
        }
        return produced
    }

    private mutating func splitOffNextSegment(force: Bool) -> String? {
        let trimmedBuffer = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBuffer.isEmpty else {
            buffer = ""
            return nil
        }

        let mode = unitMode(for: trimmedBuffer)
        let thresholds = thresholdsForCurrentStage(mode: mode)
        let fullSeconds = estimatedSeconds(for: trimmedBuffer, mode: mode)

        // Boundary-driven split: only emit when current stage minimum is reached.
        if !force && fullSeconds < thresholds.minSeconds {
            return nil
        }

        let splitIndex: String.Index
        if !force {
            splitIndex = buffer.endIndex
        } else if let punct = bestPunctuationSplitIndex(in: buffer, mode: mode, thresholds: thresholds) {
            splitIndex = punct
        } else if let byWord = bestWordBoundarySplitIndex(in: buffer, mode: mode, thresholds: thresholds) {
            splitIndex = byWord
        } else {
            splitIndex = fallbackSplitIndex(in: buffer, mode: mode, thresholds: thresholds)
        }

        let prefix = String(buffer[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.isEmpty {
            return nil
        }

        buffer = String(buffer[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        emittedSegmentCount += 1
        return prefix
    }

    private func thresholdsForCurrentStage(mode: UnitMode) -> SegmentThresholds {
        let profile = profileForCurrentStage()
        let unitRate = (mode == .cjkCharacters) ? cjkCharsPerSecond : enWordsPerSecond
        let minFloor = (mode == .cjkCharacters) ? 6 : 4

        let minUnits = max(minFloor, Int((profile.minSeconds * unitRate).rounded(.awayFromZero)))
        let preferredUnits = max(minUnits + ((mode == .cjkCharacters) ? 4 : 3),
                                 Int((profile.preferredSeconds * unitRate).rounded(.awayFromZero)))
        let maxUnits = max(preferredUnits + ((mode == .cjkCharacters) ? 6 : 5),
                           Int((profile.maxSeconds * unitRate).rounded(.awayFromZero)))

        return SegmentThresholds(
            minUnits: minUnits,
            preferredUnits: preferredUnits,
            maxUnits: maxUnits,
            minSeconds: profile.minSeconds,
            preferredSeconds: profile.preferredSeconds,
            maxSeconds: min(profile.maxSeconds, maxNormalSeconds)
        )
    }

    private func profileForCurrentStage() -> SegmentRampProfile {
        if emittedSegmentCount < rampProfiles.count {
            return rampProfiles[emittedSegmentCount]
        }
        return rampProfiles[rampProfiles.count - 1]
    }

    private func unitMode(for text: String) -> UnitMode {
        text.unicodeScalars.contains(where: { $0.properties.isIdeographic }) ? .cjkCharacters : .words
    }

    private func unitCount(in text: String, mode: UnitMode) -> Int {
        switch mode {
        case .cjkCharacters:
            return text.count
        case .words:
            return wordLikeUnitCount(text)
        }
    }

    private func estimatedSeconds(for text: String, mode: UnitMode) -> Double {
        switch mode {
        case .cjkCharacters:
            return Double(text.count) / cjkCharsPerSecond
        case .words:
            return Double(max(unitCount(in: text, mode: mode), 1)) / enWordsPerSecond
        }
    }

    /// Uses whitespace words as primary units, plus a character-based fallback so
    /// punctuation-heavy or unspaced content still advances realtime boundary flushes.
    private func wordLikeUnitCount(_ text: String) -> Int {
        let whitespaceWords = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let compactChars = text.unicodeScalars.reduce(into: 0) { count, scalar in
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                count += 1
            }
        }
        let charUnits = Int((Double(compactChars) / approxCharsPerWordUnit).rounded(.up))
        return max(whitespaceWords, charUnits)
    }

    private func bestPunctuationSplitIndex(
        in text: String,
        mode: UnitMode,
        thresholds: SegmentThresholds
    ) -> String.Index? {
        var bestIndex: String.Index?
        var bestScore = Double.greatestFiniteMagnitude

        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]
            let next = text.index(after: idx)
            guard isPunctuationBoundary(ch) else {
                idx = next
                continue
            }

            let prefix = String(text[..<next]).trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.isEmpty {
                idx = next
                continue
            }

            let units = unitCount(in: prefix, mode: mode)
            let seconds = estimatedSeconds(for: prefix, mode: mode)
            if units > thresholds.maxUnits || seconds > thresholds.maxSeconds * 1.06 {
                idx = next
                continue
            }

            // Prefer terminal punctuation and durations near the current stage target.
            let shortPenalty = max(0, thresholds.minSeconds - seconds) * 2.0
            let softPenalty = isTerminalBoundary(ch) ? 0.0 : 0.35
            let score = abs(seconds - thresholds.preferredSeconds) + shortPenalty + softPenalty

            if score < bestScore {
                bestScore = score
                bestIndex = next
            }

            idx = next
        }

        return bestIndex
    }

    private func bestWordBoundarySplitIndex(
        in text: String,
        mode: UnitMode,
        thresholds: SegmentThresholds
    ) -> String.Index? {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var bestIndex: String.Index?
        var bestScore = Double.greatestFiniteMagnitude
        var tokenCount = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokenCount += 1
            let boundary = range.upperBound
            let prefix = String(text[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { return true }

            let units: Int
            let seconds: Double
            switch mode {
            case .words:
                units = tokenCount
                seconds = Double(max(units, 1)) / enWordsPerSecond
            case .cjkCharacters:
                units = prefix.count
                seconds = Double(max(units, 1)) / cjkCharsPerSecond
            }

            guard units <= thresholds.maxUnits && seconds <= thresholds.maxSeconds * 1.08 else {
                return true
            }

            let shortPenalty = max(0, thresholds.minSeconds - seconds) * 2.2
            let score = abs(seconds - thresholds.preferredSeconds) + shortPenalty + 0.45
            if score < bestScore {
                bestScore = score
                bestIndex = boundary
            }
            return true
        }

        return bestIndex
    }

    private func fallbackSplitIndex(
        in text: String,
        mode: UnitMode,
        thresholds: SegmentThresholds
    ) -> String.Index {
        let desiredUnits = max(1, min(thresholds.maxUnits, thresholds.preferredUnits))

        switch mode {
        case .cjkCharacters:
            return indexByCharacterOffset(in: text, count: desiredUnits)
        case .words:
            // Rough fallback for extremely irregular text when tokenizer gives no tokens.
            let approxChars = max(16, desiredUnits * 6)
            return indexByCharacterOffset(in: text, count: min(approxChars, text.count))
        }
    }

    private func indexByCharacterOffset(in text: String, count: Int) -> String.Index {
        guard count > 0 else { return text.startIndex }
        return text.index(text.startIndex, offsetBy: min(count, text.count), limitedBy: text.endIndex) ?? text.endIndex
    }
}
