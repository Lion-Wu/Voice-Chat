//
//  IncrementalTextSegmenter.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

/// Groups streamed assistant text into speakable realtime segments.
/// Segment duration ramps up over the first few requests, while every split keeps
/// the original punctuation and uses a confirmed word boundary as the last resort.
struct IncrementalTextSegmenter {
    private struct SegmentProfile {
        let minimumSeconds: Double
        let preferredSeconds: Double
        let maximumSeconds: Double
    }

    private var buffer = ""
    private var inThink = false
    private var lastCharacter: Character?
    private var emittedSegmentCount = 0

    private let openMarker = "<think>"
    private let closeMarker = "</think>"

    private let profiles: [SegmentProfile] = [
        .init(minimumSeconds: 1.0, preferredSeconds: 2.2, maximumSeconds: 3.8),
        .init(minimumSeconds: 2.0, preferredSeconds: 3.8, maximumSeconds: 5.8),
        .init(minimumSeconds: 3.5, preferredSeconds: 6.0, maximumSeconds: 8.5),
        .init(minimumSeconds: 5.5, preferredSeconds: 8.5, maximumSeconds: 11.5),
        .init(minimumSeconds: 8.0, preferredSeconds: 11.5, maximumSeconds: 15.0)
    ]

    mutating func reset() {
        buffer = ""
        inThink = false
        lastCharacter = nil
        emittedSegmentCount = 0
    }

    /// Appends a streaming delta and returns completed, speakable segments.
    mutating func append(_ delta: String) -> [String] {
        guard !delta.isEmpty else { return [] }

        var index = delta.startIndex
        while index < delta.endIndex {
            if isStandaloneMarker(delta, at: index, marker: openMarker) {
                inThink = true
                lastCharacter = delta[delta.index(index, offsetBy: openMarker.count - 1)]
                index = delta.index(index, offsetBy: openMarker.count)
                continue
            }
            if isStandaloneMarker(delta, at: index, marker: closeMarker) {
                inThink = false
                lastCharacter = delta[delta.index(index, offsetBy: closeMarker.count - 1)]
                index = delta.index(index, offsetBy: closeMarker.count)
                continue
            }

            let character = delta[index]
            if !inThink {
                buffer.append(character)
            }
            lastCharacter = character
            index = delta.index(after: index)
        }

        return drainReadySegments(allowBoundaryAtBufferEnd: false)
    }

    /// Flushes any remaining text when the assistant stream ends.
    mutating func finalize() -> [String] {
        var produced = drainReadySegments(allowBoundaryAtBufferEnd: true)

        while !buffer.isEmpty {
            let durationIndex = SpeechTextSegmentation.DurationIndex(text: buffer)
            guard durationIndex.estimatedSeconds(
                from: buffer.startIndex,
                to: buffer.endIndex
            ) > currentProfile.maximumSeconds else {
                break
            }
            guard let boundary = preferredForcedBoundary(
                in: buffer,
                profile: currentProfile,
                durationIndex: durationIndex
            ) else {
                break
            }
            guard let segment = emitPrefix(endingAt: boundary) else { break }
            produced.append(segment)
        }

        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        if !tail.isEmpty {
            produced.append(tail)
            emittedSegmentCount += 1
        }
        return produced
    }

    // MARK: - Stream parsing

    /// A think marker is control syntax only when it occupies its own line.
    private func isStandaloneMarker(_ delta: String, at index: String.Index, marker: String) -> Bool {
        guard delta[index...].hasPrefix(marker) else { return false }

        let beforeCharacter: Character?
        if index == delta.startIndex {
            beforeCharacter = lastCharacter
        } else {
            beforeCharacter = delta[delta.index(before: index)]
        }
        guard beforeCharacter == nil || beforeCharacter?.isNewline == true else { return false }

        let afterIndex = delta.index(index, offsetBy: marker.count)
        return afterIndex == delta.endIndex || delta[afterIndex].isNewline
    }

    // MARK: - Segment selection

    private var currentProfile: SegmentProfile {
        profiles[min(emittedSegmentCount, profiles.count - 1)]
    }

    private mutating func drainReadySegments(allowBoundaryAtBufferEnd: Bool) -> [String] {
        var produced: [String] = []

        while !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let profile = currentProfile
            let durationIndex = SpeechTextSegmentation.DurationIndex(text: buffer)
            let terminalBoundary = eligibleTerminalBoundary(
                in: buffer,
                profile: profile,
                durationIndex: durationIndex,
                allowBoundaryAtBufferEnd: allowBoundaryAtBufferEnd
            )

            if let terminalBoundary {
                let duration = durationIndex.estimatedSeconds(
                    from: buffer.startIndex,
                    to: terminalBoundary
                )
                if duration <= profile.maximumSeconds * 1.15 {
                    guard let segment = emitPrefix(endingAt: terminalBoundary) else { break }
                    produced.append(segment)
                    continue
                }
            }

            let bufferedDuration = durationIndex.estimatedSeconds(
                from: buffer.startIndex,
                to: buffer.endIndex
            )
            guard bufferedDuration >= profile.maximumSeconds else { break }

            if let forcedBoundary = preferredForcedBoundary(
                in: buffer,
                profile: profile,
                durationIndex: durationIndex
            ),
               let segment = emitPrefix(endingAt: forcedBoundary) {
                produced.append(segment)
                continue
            }

            // No safe boundary is visible yet. Keep buffering rather than cutting a
            // partially streamed word; the next delta normally supplies its boundary.
            if let terminalBoundary,
               let segment = emitPrefix(endingAt: terminalBoundary) {
                produced.append(segment)
                continue
            }
            break
        }
        return produced
    }

    private func eligibleTerminalBoundary(
        in text: String,
        profile: SegmentProfile,
        durationIndex: SpeechTextSegmentation.DurationIndex,
        allowBoundaryAtBufferEnd: Bool
    ) -> String.Index? {
        let boundaries = SpeechTextSegmentation.terminalBoundaries(in: text)
        let twoSentenceMinimum = max(1.0, min(4.0, profile.minimumSeconds * 0.5))

        for (offset, boundary) in boundaries.enumerated() {
            let duration = durationIndex.estimatedSeconds(
                from: text.startIndex,
                to: boundary
            )
            guard allowBoundaryAtBufferEnd ||
                    boundary < text.endIndex ||
                    duration >= profile.maximumSeconds else {
                continue
            }
            if duration >= profile.minimumSeconds ||
               (offset >= 1 && duration >= twoSentenceMinimum) {
                return boundary
            }
        }
        return nil
    }

    private func preferredForcedBoundary(
        in text: String,
        profile: SegmentProfile,
        durationIndex: SpeechTextSegmentation.DurationIndex
    ) -> String.Index? {
        let minimumUsefulDuration = max(0.8, profile.minimumSeconds * 0.7)
        let punctuation = bestBoundary(
            SpeechTextSegmentation.punctuationBoundaries(in: text),
            in: text,
            profile: profile,
            durationIndex: durationIndex,
            minimumDuration: minimumUsefulDuration
        )
        if let punctuation { return punctuation }

        return bestBoundary(
            SpeechTextSegmentation.wordBoundaries(in: text, excludingEnd: true),
            in: text,
            profile: profile,
            durationIndex: durationIndex,
            minimumDuration: minimumUsefulDuration
        )
    }

    private func bestBoundary(
        _ boundaries: [String.Index],
        in text: String,
        profile: SegmentProfile,
        durationIndex: SpeechTextSegmentation.DurationIndex,
        minimumDuration: Double
    ) -> String.Index? {
        var best: (index: String.Index, score: Double)?

        for boundary in boundaries where boundary > text.startIndex && boundary < text.endIndex {
            let duration = durationIndex.estimatedSeconds(from: text.startIndex, to: boundary)
            if duration > profile.maximumSeconds { break }
            guard duration >= minimumDuration else { continue }
            let score = abs(duration - profile.preferredSeconds)
            if best == nil || score < best!.score {
                best = (boundary, score)
            }
        }
        return best?.index
    }

    private mutating func emitPrefix(endingAt boundary: String.Index) -> String? {
        let prefix = String(buffer[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return nil }

        buffer = String(buffer[boundary...])
        emittedSegmentCount += 1
        return prefix
    }
}
