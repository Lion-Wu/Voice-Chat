//
//  VoiceVisionSampleSelector.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

enum VoiceVisionSampleSelector {
    static let maxStoredSamples = 72

    static func selectedAttachments(
        from samples: [VoiceVisionCaptureSample],
        startedAt: Date?,
        now: Date = Date(),
        isAvailable: Bool
    ) -> [ChatImageAttachment] {
        guard isAvailable, !samples.isEmpty else { return [] }

        let duration = utteranceDuration(samples: samples, startedAt: startedAt, now: now)
        let desiredCount = desiredAttachmentCount(forDuration: duration)
        let selectedSamples = evenlyDownsampled(samples, limit: desiredCount)
        return selectedSamples.map(\.attachment)
    }

    static func estimatedAttachmentCount(
        from samples: [VoiceVisionCaptureSample],
        startedAt: Date?,
        now: Date = Date(),
        isAvailable: Bool
    ) -> Int {
        guard isAvailable, !samples.isEmpty else { return 0 }
        let duration = utteranceDuration(samples: samples, startedAt: startedAt, now: now)
        return min(samples.count, desiredAttachmentCount(forDuration: duration))
    }

    static func evenlyDownsampled(
        _ samples: [VoiceVisionCaptureSample],
        limit: Int
    ) -> [VoiceVisionCaptureSample] {
        guard samples.count > limit else { return samples }
        guard limit > 1 else { return [samples[samples.count / 2]] }

        var result: [VoiceVisionCaptureSample] = []
        result.reserveCapacity(limit)
        for index in 0..<limit {
            let fraction = Double(index) / Double(limit - 1)
            let sampleIndex = Int(round(fraction * Double(samples.count - 1)))
            result.append(samples[min(max(0, sampleIndex), samples.count - 1)])
        }
        return result
    }

    static func desiredAttachmentCount(forDuration duration: TimeInterval) -> Int {
        max(1, min(9, Int(ceil(duration / 2.0))))
    }

    static func normalizedMIMEType(_ mimeType: String?) -> String {
        let normalized = mimeType?
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "image/jpg" {
            return "image/jpeg"
        }
        if let normalized, !normalized.isEmpty {
            return normalized
        }
        return "image/jpeg"
    }

    private static func utteranceDuration(
        samples: [VoiceVisionCaptureSample],
        startedAt: Date?,
        now: Date
    ) -> TimeInterval {
        let start = startedAt ?? samples.first?.capturedAt ?? now
        return max(1, now.timeIntervalSince(start))
    }
}
