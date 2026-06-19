//
//  VoiceVisionSampleSelector.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
#if os(iOS) || os(macOS)
import CoreGraphics
import ImageIO
#endif

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
        let selectedSamples = visuallyDiverseSamples(samples, limit: desiredCount)
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
        let desiredCount = desiredAttachmentCount(forDuration: duration)
        return visuallyDiverseSamples(samples, limit: desiredCount).count
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
        desiredAttachmentCount(
            forDuration: duration,
            maximumCount: VoiceVisionCaptureTuning.maximumAttachmentCount
        )
    }

    static func desiredAttachmentCount(
        forDuration duration: TimeInterval,
        maximumCount: Int
    ) -> Int {
        guard maximumCount > 1 else { return max(0, maximumCount) }

        let duration = max(0, duration)
        guard duration < VoiceVisionCaptureTuning.attachmentCountSaturationDuration else {
            return maximumCount
        }

        let progress = duration / VoiceVisionCaptureTuning.attachmentCountSaturationDuration
        let attachmentSteps = maximumCount - 1
        let curveStrength = max(1.0, Double(attachmentSteps) * 1.5)
        let curvedProgress = log1p(curveStrength * progress) / log1p(curveStrength)
        let curvedCount = 1 + Int(round(Double(attachmentSteps) * curvedProgress))
        return max(1, min(maximumCount, curvedCount))
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

    private static func visuallyDiverseSamples(
        _ samples: [VoiceVisionCaptureSample],
        limit: Int
    ) -> [VoiceVisionCaptureSample] {
        guard !samples.isEmpty else { return [] }
        guard limit > 0 else { return [] }

        #if os(iOS) || os(macOS)
        let fingerprintedSamples = samples.enumerated().compactMap { index, sample -> FingerprintedSample? in
            guard let fingerprint = sample.visualFingerprint else { return nil }
            return FingerprintedSample(index: index, sample: sample, fingerprint: fingerprint)
        }
        guard fingerprintedSamples.count == samples.count else {
            return evenlyDownsampled(samples, limit: limit)
        }

        var selected: [FingerprintedSample] = [fingerprintedSamples[fingerprintedSamples.count - 1]]
        let cappedLimit = min(limit, fingerprintedSamples.count)
        while selected.count < cappedLimit {
            let next = fingerprintedSamples
                .filter { candidate in !selected.contains(where: { $0.index == candidate.index }) }
                .map { candidate -> (sample: FingerprintedSample, distance: Double) in
                    let distance = selected
                        .map { visualDistance(candidate.fingerprint, $0.fingerprint) }
                        .min() ?? .greatestFiniteMagnitude
                    return (candidate, distance)
                }
                .max { lhs, rhs in
                    if lhs.distance == rhs.distance {
                        return lhs.sample.index < rhs.sample.index
                    }
                    return lhs.distance < rhs.distance
                }

            guard let next, next.distance >= VoiceVisionCaptureTuning.selectionDistinctThreshold else {
                break
            }
            selected.append(next.sample)
        }

        return selected
            .sorted { $0.index < $1.index }
            .map(\.sample)
        #else
        return evenlyDownsampled(samples, limit: limit)
        #endif
    }

    static func visualFingerprint(from imageData: Data) -> VoiceVisionVisualFingerprint? {
        #if os(iOS) || os(macOS)
        return platformVisualFingerprint(from: imageData)
        #else
        return nil
        #endif
    }

    #if os(iOS) || os(macOS)
    private struct FingerprintedSample {
        let index: Int
        let sample: VoiceVisionCaptureSample
        let fingerprint: VoiceVisionVisualFingerprint
    }

    private static func platformVisualFingerprint(from imageData: Data) -> VoiceVisionVisualFingerprint? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: VoiceVisionCaptureTuning.fingerprintImageMaxPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let grid = VoiceVisionCaptureTuning.fingerprintGridDimension
        let subsamples = VoiceVisionCaptureTuning.fingerprintSubsamplesPerCell
        var luminance: [UInt8] = []
        luminance.reserveCapacity(grid * grid)

        for row in 0..<grid {
            for column in 0..<grid {
                var total = 0
                var count = 0

                for sampleY in 0..<subsamples {
                    let y = cellSampleCoordinate(
                        length: height,
                        gridIndex: row,
                        gridCount: grid,
                        sampleIndex: sampleY,
                        sampleCount: subsamples
                    )
                    for sampleX in 0..<subsamples {
                        let x = cellSampleCoordinate(
                            length: width,
                            gridIndex: column,
                            gridCount: grid,
                            sampleIndex: sampleX,
                            sampleCount: subsamples
                        )
                        let offset = y * bytesPerRow + x * 4
                        let red = Int(pixels[offset])
                        let green = Int(pixels[offset + 1])
                        let blue = Int(pixels[offset + 2])
                        total += (77 * red + 150 * green + 29 * blue) >> 8
                        count += 1
                    }
                }

                luminance.append(UInt8(clamping: count == 0 ? 0 : total / count))
            }
        }

        return VoiceVisionVisualFingerprint(luminance: luminance)
    }

    private static func cellSampleCoordinate(
        length: Int,
        gridIndex: Int,
        gridCount: Int,
        sampleIndex: Int,
        sampleCount: Int
    ) -> Int {
        let cellStart = (length * gridIndex) / gridCount
        let cellEnd = (length * (gridIndex + 1)) / gridCount
        let cellLength = max(1, cellEnd - cellStart)
        let offset = (cellLength * ((sampleIndex * 2) + 1)) / (sampleCount * 2)
        return min(length - 1, cellStart + offset)
    }

    private static func visualDistance(
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

        var bestDistance = Double.greatestFiniteMagnitude
        for yOffset in -1...1 {
            for xOffset in -1...1 {
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
        return (Double(totalDifference) / Double(comparedCount)) + (missingFraction * 20.0)
    }
    #endif
}
