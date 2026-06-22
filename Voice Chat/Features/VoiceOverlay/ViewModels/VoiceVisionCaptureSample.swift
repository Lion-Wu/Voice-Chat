//
//  VoiceVisionCaptureSample.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct VoiceVisionVisualFingerprint: Equatable, Sendable {
    let luminance: [UInt8]

    static func visualDistance(
        _ lhs: VoiceVisionVisualFingerprint,
        _ rhs: VoiceVisionVisualFingerprint
    ) -> Double {
        guard lhs.luminance.count == rhs.luminance.count, !lhs.luminance.isEmpty else {
            return .greatestFiniteMagnitude
        }

        let grid = VoiceVisionCaptureTuning.fingerprintGridDimension
        guard lhs.luminance.count == grid * grid else {
            return meanAbsoluteDistance(lhs.luminance, rhs.luminance)
        }

        let maxOffset = max(
            1,
            min(grid - 1, Int((Double(grid) * VoiceVisionCaptureTuning.fingerprintMaxShiftFraction).rounded(.down)))
        )
        var bestDistance = Double.greatestFiniteMagnitude
        for yOffset in -maxOffset...maxOffset {
            for xOffset in -maxOffset...maxOffset {
                bestDistance = min(
                    bestDistance,
                    shiftedVisualDistance(lhs, rhs, grid: grid, xOffset: xOffset, yOffset: yOffset)
                )
            }
        }
        return bestDistance
    }

    private static func meanAbsoluteDistance(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        let totalDifference = zip(lhs, rhs).reduce(0) { result, pair in
            result + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(totalDifference) / Double(lhs.count)
    }

    private static func shiftedVisualDistance(
        _ lhs: VoiceVisionVisualFingerprint,
        _ rhs: VoiceVisionVisualFingerprint,
        grid: Int,
        xOffset: Int,
        yOffset: Int
    ) -> Double {
        var totalDifference = 0
        var comparedCount = 0

        for y in 0..<grid {
            let shiftedY = y + yOffset
            guard shiftedY >= 0, shiftedY < grid else { continue }

            for x in 0..<grid {
                let shiftedX = x + xOffset
                guard shiftedX >= 0, shiftedX < grid else { continue }

                let lhsValue = lhs.luminance[y * grid + x]
                let rhsValue = rhs.luminance[shiftedY * grid + shiftedX]
                totalDifference += abs(Int(lhsValue) - Int(rhsValue))
                comparedCount += 1
            }
        }

        guard comparedCount > 0 else { return .greatestFiniteMagnitude }
        let missingFraction = 1.0 - (Double(comparedCount) / Double(grid * grid))
        return (Double(totalDifference) / Double(comparedCount))
            + (missingFraction * VoiceVisionCaptureTuning.fingerprintShiftCoveragePenalty)
    }
}

struct VoiceVisionCaptureSample: Equatable, Sendable {
    let capturedAt: Date
    let attachment: ChatImageAttachment
    let visualFingerprint: VoiceVisionVisualFingerprint?

    init(
        capturedAt: Date,
        attachment: ChatImageAttachment,
        visualFingerprint: VoiceVisionVisualFingerprint? = nil
    ) {
        self.capturedAt = capturedAt
        self.attachment = attachment
        self.visualFingerprint = visualFingerprint
    }
}
