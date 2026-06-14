#if os(iOS) || os(macOS)

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation

final class VoiceVisionFrameSampler {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var recentAcceptedFingerprints: [VisualFingerprint] = []

    private static let sampledImageMaxPixelSize: CGFloat = 960
    private static let jpegCompressionQuality: CGFloat = 0.68
    private static let fingerprintGridDimension = 8
    private static let visualChangeThreshold: Double = 10.0
    private static let maxRecentAcceptedFingerprints = 9

    private struct VisualFingerprint {
        let luminance: [UInt8]
    }

    func resetVisualHistory() {
        recentAcceptedFingerprints.removeAll()
    }

    func encodedAcceptedJPEGData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let fingerprint = visualFingerprint(from: pixelBuffer)
        guard shouldAcceptVisualFingerprint(fingerprint) else { return nil }

        let data = encodedJPEGData(from: pixelBuffer)
        if !(data?.isEmpty ?? true) {
            recordAcceptedVisualFingerprint(fingerprint)
        }
        return data
    }

    private func encodedJPEGData(from pixelBuffer: CVPixelBuffer) -> Data? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let longestSide = max(image.extent.width, image.extent.height)
        if longestSide > Self.sampledImageMaxPixelSize {
            let scale = Self.sampledImageMaxPixelSize / longestSide
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        guard let cgImage = ciContext.createCGImage(image, from: image.extent.integral) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options = [
            kCGImageDestinationLossyCompressionQuality as String: Self.jpegCompressionQuality
        ] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func visualFingerprint(from pixelBuffer: CVPixelBuffer) -> VisualFingerprint? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let grid = Self.fingerprintGridDimension
        var luminance: [UInt8] = []
        luminance.reserveCapacity(grid * grid)

        for row in 0..<grid {
            let y = min(height - 1, (height * ((row * 2) + 1)) / (grid * 2))
            for column in 0..<grid {
                let x = min(width - 1, (width * ((column * 2) + 1)) / (grid * 2))
                let offset = (y * bytesPerRow) + (x * 4)
                let blue = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let red = Int(bytes[offset + 2])
                let value = (77 * red + 150 * green + 29 * blue) >> 8
                luminance.append(UInt8(clamping: value))
            }
        }

        return VisualFingerprint(luminance: luminance)
    }

    private func shouldAcceptVisualFingerprint(_ fingerprint: VisualFingerprint?) -> Bool {
        guard let fingerprint else { return true }
        guard !recentAcceptedFingerprints.isEmpty else { return true }

        let nearestDistance = recentAcceptedFingerprints
            .map { visualDistance(fingerprint, $0) }
            .min() ?? .greatestFiniteMagnitude
        return nearestDistance >= Self.visualChangeThreshold
    }

    private func recordAcceptedVisualFingerprint(_ fingerprint: VisualFingerprint?) {
        guard let fingerprint else { return }
        recentAcceptedFingerprints.append(fingerprint)
        if recentAcceptedFingerprints.count > Self.maxRecentAcceptedFingerprints {
            recentAcceptedFingerprints.removeFirst(recentAcceptedFingerprints.count - Self.maxRecentAcceptedFingerprints)
        }
    }

    private func visualDistance(_ lhs: VisualFingerprint, _ rhs: VisualFingerprint) -> Double {
        guard lhs.luminance.count == rhs.luminance.count, !lhs.luminance.isEmpty else {
            return .greatestFiniteMagnitude
        }

        let totalDifference = zip(lhs.luminance, rhs.luminance).reduce(0) { result, pair in
            result + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(totalDifference) / Double(lhs.luminance.count)
    }
}

#endif
