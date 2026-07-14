import XCTest
@testable import Voice_Chat

final class TTSPresetApplyStatusTests: XCTestCase {
    func testStartingClearsPreviousResultAndRetryState() {
        let previous = TTSPresetApplyStatus(
            isApplying: false,
            isRetrying: true,
            retryAttempt: 2,
            retryLastError: "timeout",
            lastError: "failed",
            lastAppliedAt: TestDate.reference,
            lastSucceeded: true
        )

        let started = previous.starting()

        XCTAssertTrue(started.isApplying)
        XCTAssertFalse(started.isRetrying)
        XCTAssertEqual(started.retryAttempt, 0)
        XCTAssertNil(started.retryLastError)
        XCTAssertNil(started.lastError)
        XCTAssertNil(started.lastAppliedAt)
        XCTAssertFalse(started.lastSucceeded)
    }

    func testRetryStatusCanBeSetAndCleared() {
        let retrying = TTSPresetApplyStatus.idle
            .starting()
            .updatingRetry(TTSPresetApplyRetryStatus(nextAttempt: 3, errorDescription: "offline"))

        XCTAssertTrue(retrying.isRetrying)
        XCTAssertEqual(retrying.retryAttempt, 2)
        XCTAssertEqual(retrying.retryLastError, "offline")

        let cleared = retrying.updatingRetry(nil)

        XCTAssertFalse(cleared.isRetrying)
        XCTAssertEqual(cleared.retryAttempt, 0)
        XCTAssertNil(cleared.retryLastError)
    }

    func testFinalStatesStopApplyingAndRecordOutcome() {
        let date = TestDate.reference
        let failure = TTSPresetApplyStatus.idle
            .starting()
            .updatingRetry(TTSPresetApplyRetryStatus(nextAttempt: 2, errorDescription: "retry"))
            .recordingFailure("failed", at: date)

        XCTAssertFalse(failure.isApplying)
        XCTAssertFalse(failure.isRetrying)
        XCTAssertEqual(failure.lastError, "failed")
        XCTAssertEqual(failure.lastAppliedAt, date)
        XCTAssertFalse(failure.lastSucceeded)

        let success = TTSPresetApplyStatus.idle
            .starting()
            .recordingSuccess(at: date)

        XCTAssertFalse(success.isApplying)
        XCTAssertNil(success.lastError)
        XCTAssertEqual(success.lastAppliedAt, date)
        XCTAssertTrue(success.lastSucceeded)
    }
}
