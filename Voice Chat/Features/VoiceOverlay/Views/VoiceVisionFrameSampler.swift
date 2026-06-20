#if os(iOS) || os(macOS)

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation

struct VoiceVisionEncodedSample: Sendable {
    let data: Data
    let visualFingerprint: VoiceVisionVisualFingerprint?
}

final class VoiceVisionFrameSampler {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var recentEncodedFingerprints: [VoiceVisionVisualFingerprint] = []

    func resetVisualHistory() {
        recentEncodedFingerprints.removeAll()
    }

    func encodedAcceptedSample(from pixelBuffer: CVPixelBuffer) -> VoiceVisionEncodedSample? {
        let fingerprint = visualFingerprint(from: pixelBuffer)
        guard shouldEncode(fingerprint) else { return nil }
        guard let data = encodedJPEGData(from: pixelBuffer), !data.isEmpty else { return nil }
        recordEncodedFingerprint(fingerprint)
        return VoiceVisionEncodedSample(data: data, visualFingerprint: fingerprint)
    }

    private func shouldEncode(_ fingerprint: VoiceVisionVisualFingerprint?) -> Bool {
        guard let fingerprint else { return true }
        guard !recentEncodedFingerprints.isEmpty else { return true }
        let nearestDistance = recentEncodedFingerprints
            .map { VoiceVisionVisualFingerprint.visualDistance(fingerprint, $0) }
            .min() ?? .greatestFiniteMagnitude
        return nearestDistance >= VoiceVisionCaptureTuning.encodingDuplicateThreshold
    }

    private func recordEncodedFingerprint(_ fingerprint: VoiceVisionVisualFingerprint?) {
        guard let fingerprint else { return }
        recentEncodedFingerprints.append(fingerprint)
        let limit = VoiceVisionCaptureTuning.maxRecentEncodedFingerprints
        if recentEncodedFingerprints.count > limit {
            recentEncodedFingerprints.removeFirst(recentEncodedFingerprints.count - limit)
        }
    }

    private func encodedJPEGData(from pixelBuffer: CVPixelBuffer) -> Data? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let longestSide = max(image.extent.width, image.extent.height)
        if longestSide > CGFloat(VoiceVisionCaptureTuning.sampledImageMaxPixelSize) {
            let scale = CGFloat(VoiceVisionCaptureTuning.sampledImageMaxPixelSize) / longestSide
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
            kCGImageDestinationLossyCompressionQuality as String: VoiceVisionCaptureTuning.jpegCompressionQuality
        ] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func visualFingerprint(from pixelBuffer: CVPixelBuffer) -> VoiceVisionVisualFingerprint? {
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
                        let offset = (y * bytesPerRow) + (x * 4)
                        let blue = Int(bytes[offset])
                        let green = Int(bytes[offset + 1])
                        let red = Int(bytes[offset + 2])
                        total += (77 * red + 150 * green + 29 * blue) >> 8
                        count += 1
                    }
                }

                luminance.append(UInt8(clamping: count == 0 ? 0 : total / count))
            }
        }

        return VoiceVisionVisualFingerprint(luminance: luminance)
    }

    private func cellSampleCoordinate(
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

}

#endif
