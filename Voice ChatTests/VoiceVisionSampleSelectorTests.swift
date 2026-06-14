import XCTest
@testable import Voice_Chat

final class VoiceVisionSampleSelectorTests: XCTestCase {
    func testDesiredAttachmentCountScalesAndCaps() {
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 0.2), 1)
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 3.1), 2)
        XCTAssertEqual(VoiceVisionSampleSelector.desiredAttachmentCount(forDuration: 60), 9)
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
        XCTAssertEqual(selected.map(\.data), [Data([0]), Data([2]), Data([5]), Data([7]), Data([9])])

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
        XCTAssertEqual(VoiceVisionSampleSelector.normalizedMIMEType(" image/jpg; charset=binary "), "image/jpeg")
        XCTAssertEqual(VoiceVisionSampleSelector.normalizedMIMEType(nil), "image/jpeg")
    }

    private func sampleRange(_ range: Range<Int>, start: Date = Date(timeIntervalSince1970: 0)) -> [VoiceVisionCaptureSample] {
        range.map { index in
            VoiceVisionCaptureSample(
                capturedAt: start.addingTimeInterval(Double(index)),
                attachment: ChatImageAttachment(mimeType: "image/jpeg", data: Data([UInt8(index)]))
            )
        }
    }
}
