import XCTest
@testable import Voice_Chat

@MainActor
final class VoiceVisionCaptureCoordinatorTests: XCTestCase {
    func testPresentationRequiresImageCapableSession() {
        var coordinator = VoiceVisionCaptureCoordinator()

        XCTAssertFalse(coordinator.present(
            isAvailable: false,
            isRecording: true,
            isSendSuppressed: false
        ))
        XCTAssertFalse(coordinator.state.isPresented)
        XCTAssertFalse(coordinator.state.isRecording)
    }

    func testHeldUtteranceKeepsSamplesAcrossRecordingPause() {
        var coordinator = VoiceVisionCaptureCoordinator()
        let start = TestDate.reference

        XCTAssertTrue(coordinator.present(
            isAvailable: true,
            isRecording: true,
            isSendSuppressed: true,
            now: start
        ))
        coordinator.appendSample(
            data: Data([1]),
            mimeType: "image/png",
            isAvailable: true,
            now: start.addingTimeInterval(0.5)
        )

        coordinator.updateRecordingState(
            isRecording: false,
            isAvailable: true,
            isSendSuppressed: true
        )
        coordinator.beginUtteranceIfNeeded(
            isAvailable: true,
            isSendSuppressed: true,
            now: start.addingTimeInterval(2)
        )
        coordinator.appendSample(
            data: Data([2]),
            mimeType: nil,
            isAvailable: true,
            now: start.addingTimeInterval(2.5)
        )

        let selected = coordinator.selectedAttachments(
            isAvailable: true,
            now: start.addingTimeInterval(4)
        )
        XCTAssertEqual(selected.map(\.data), [Data([1]), Data([2])])
        XCTAssertEqual(coordinator.state.sampleCount, 2)
    }

    func testNonSuppressedUtteranceRestartClearsPreviousSamples() {
        var coordinator = VoiceVisionCaptureCoordinator()
        let start = TestDate.reference
        let firstResetID: UUID

        XCTAssertTrue(coordinator.present(
            isAvailable: true,
            isRecording: true,
            isSendSuppressed: false,
            now: start
        ))
        firstResetID = coordinator.state.resetID
        coordinator.appendSample(data: Data([1]), mimeType: nil, isAvailable: true, now: start)

        coordinator.updateRecordingState(
            isRecording: false,
            isAvailable: true,
            isSendSuppressed: false
        )
        coordinator.beginUtteranceIfNeeded(
            isAvailable: true,
            isSendSuppressed: false,
            now: start.addingTimeInterval(2)
        )
        coordinator.appendSample(
            data: Data([9]),
            mimeType: nil,
            isAvailable: true,
            now: start.addingTimeInterval(3)
        )

        let selected = coordinator.selectedAttachments(
            isAvailable: true,
            now: start.addingTimeInterval(4)
        )
        XCTAssertEqual(selected.map(\.data), [Data([9])])
        XCTAssertNotEqual(coordinator.state.resetID, firstResetID)
    }

    func testDismissResetsVisibleStateAndSamples() {
        var coordinator = VoiceVisionCaptureCoordinator()
        let start = TestDate.reference

        XCTAssertTrue(coordinator.present(
            isAvailable: true,
            isRecording: true,
            isSendSuppressed: false,
            now: start
        ))
        coordinator.appendSample(data: Data([1]), mimeType: nil, isAvailable: true, now: start)
        coordinator.dismiss()

        XCTAssertFalse(coordinator.state.isPresented)
        XCTAssertFalse(coordinator.state.isRecording)
        XCTAssertEqual(coordinator.state.sampleCount, 0)
        XCTAssertTrue(coordinator.selectedAttachments(isAvailable: true, now: start).isEmpty)
    }
}
