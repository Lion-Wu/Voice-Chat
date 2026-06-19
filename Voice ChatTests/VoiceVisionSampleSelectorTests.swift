import XCTest
@testable import Voice_Chat
#if os(iOS) || os(macOS)
import CoreGraphics
import ImageIO
#endif

final class VoiceVisionSampleSelectorTests: XCTestCase {
    func testCaptureTuningSamplesEveryTwoSeconds() {
        #if os(iOS) || os(macOS)
        XCTAssertEqual(VoiceVisionCaptureTuning.sampleInterval, 2.0)
        #endif
    }

    func testDesiredAttachmentCountScalesAndCaps() {
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 0.2), 1)
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 3.1), 3)
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 10), 4)
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 17), 6)
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 30), 7)
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 59), 9)
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 60), 9)
    }

    func testDesiredAttachmentCountAdaptsToMaximumAttachmentCount() {
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 60, maximumCount: 4), 4)
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 60, maximumCount: 12), 12)
        XCTAssertLessThanOrEqual(
            VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 30, maximumCount: 12),
            12
        )
        XCTAssertLessThan(
            VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 3.1, maximumCount: 12),
            VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 30, maximumCount: 12)
        )
    }

    func testSelectedAttachmentsPreferVisuallyDistinctSamplesInTimeOrder() throws {
        #if os(iOS) || os(macOS)
        let start = Date(timeIntervalSince1970: 100)
        let samples = [
            imageSample(gray: 96, capturedAt: start),
            imageSample(gray: 108, capturedAt: start.addingTimeInterval(2)),
            imageSample(gray: 144, capturedAt: start.addingTimeInterval(4))
        ]

        let selected = VoiceVisionSampleSelector.selectedAttachments(
            from: samples,
            startedAt: start,
            now: start.addingTimeInterval(30),
            isAvailable: true
        )

        XCTAssertEqual(selected.map(\.data), [
            samples[0].attachment.data,
            samples[2].attachment.data
        ])
        #endif
    }

    func testSelectedAttachmentsTreatsSmallCameraShiftAsSimilar() throws {
        #if os(iOS) || os(macOS)
        let start = Date(timeIntervalSince1970: 100)
        let samples = [
            imageSample(splitAt: 28, capturedAt: start),
            imageSample(splitAt: 36, capturedAt: start.addingTimeInterval(2))
        ]

        let selected = VoiceVisionSampleSelector.selectedAttachments(
            from: samples,
            startedAt: start,
            now: start.addingTimeInterval(30),
            isAvailable: true
        )

        XCTAssertEqual(selected.map(\.data), [samples[1].attachment.data])
        #endif
    }

    func testEvenlyDownsampledKeepsSpreadAcrossUtterance() {
        let samples = sampleRange(0..<10)
        let selected = VoiceVisionSampleSelector.evenlyDownsampled(samples, limit: 3)

        XCTAssertEqual(selected.map { $0.attachment.data }, [Data([0]), Data([5]), Data([9])])
    }

    func testSelectedAttachmentsUsesDurationAndAvailability() {
        let start = Date(timeIntervalSince1970: 100)
        let samples = sampleRange(0..<10, start: start)

        let selected = VoiceVisionSampleSelector.selectedAttachments(
            from: samples,
            startedAt: start,
            now: start.addingTimeInterval(10),
            isAvailable: true
        )
        XCTAssertEqual(selected.map(\.data), [Data([0]), Data([3]), Data([6]), Data([9])])

        XCTAssertTrue(VoiceVisionSampleSelector.selectedAttachments(
            from: samples,
            startedAt: start,
            now: start.addingTimeInterval(10),
            isAvailable: false
        ).isEmpty)
    }

    func testEstimatedCountAndMIMETypeNormalization() {
        let start = Date(timeIntervalSince1970: 100)
        let samples = sampleRange(0..<10, start: start)

        XCTAssertEqual(VoiceVisionSampleSelector.estimatedAttachmentCount(
            from: samples,
            startedAt: start,
            now: start.addingTimeInterval(5),
            isAvailable: true
        ), 3)
        XCTAssertEqual(VoiceVisionSampleSelector.estimatedAttachmentCount(
            from: samples,
            startedAt: start,
            now: start.addingTimeInterval(17),
            isAvailable: true
        ), 6)
        XCTAssertEqual(VoiceVisionSampleSelector.normalizedMIMEType(" image/jpg; charset=binary "), "image/jpeg")
        XCTAssertEqual(VoiceVisionSampleSelector.normalizedMIMEType(nil), "image/jpeg")
    }

    private func sampleRange(
        _ range: Range<Int>,
        start: Date = Date(timeIntervalSince1970: 0)
    ) -> [VoiceVisionCaptureSample] {
        range.map { index in
            VoiceVisionCaptureSample(
                capturedAt: start.addingTimeInterval(Double(index)),
                attachment: ChatImageAttachment(mimeType: "image/jpeg", data: Data([UInt8(index)]))
            )
        }
    }

    #if os(iOS) || os(macOS)
    private func imageSample(gray: UInt8, capturedAt: Date) -> VoiceVisionCaptureSample {
        let data = makeJPEGData(gray: gray)
        return VoiceVisionCaptureSample(
            capturedAt: capturedAt,
            attachment: ChatImageAttachment(mimeType: "image/jpeg", data: data),
            visualFingerprint: VoiceVisionSampleSelector.visualFingerprint(from: data)
        )
    }

    private func imageSample(splitAt: Int, capturedAt: Date) -> VoiceVisionCaptureSample {
        let data = makeJPEGData { x, _ in
            x < splitAt ? 32 : 224
        }
        return VoiceVisionCaptureSample(
            capturedAt: capturedAt,
            attachment: ChatImageAttachment(mimeType: "image/jpeg", data: data),
            visualFingerprint: VoiceVisionSampleSelector.visualFingerprint(from: data)
        )
    }

    private func makeJPEGData(gray: UInt8, width: Int = 32, height: Int = 32) -> Data {
        makeJPEGData(width: width, height: height) { _, _ in gray }
    }

    private func makeJPEGData(
        width: Int = 64,
        height: Int = 64,
        luminance: (Int, Int) -> UInt8
    ) -> Data {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let gray = luminance(x, y)
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = gray
                pixels[offset + 1] = gray
                pixels[offset + 2] = gray
                pixels[offset + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
        let image = context?.makeImage()
        XCTAssertNotNil(image)

        let data = NSMutableData()
        guard let image,
              let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    #endif
}
