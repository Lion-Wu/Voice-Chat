import XCTest
@testable import Voice_Chat

final class TTSRequestRetryStateTests: XCTestCase {
    func testMarkScheduledPublishesTrimmedRetryState() {
        var state = TTSRequestRetryState()

        let published = state.markScheduled(
            index: 2,
            attempt: state.nextAttempt(for: 2),
            lastErrorMessage: "  timeout  "
        )

        XCTAssertTrue(published.isRetrying)
        XCTAssertEqual(published.retryAttempt, 1)
        XCTAssertEqual(published.retryLastError, "timeout")
        XCTAssertEqual(state.nextAttempt(for: 2), 2)
    }

    func testClearKeepsLastErrorWhileOtherRetriesRemain() {
        var state = TTSRequestRetryState()
        _ = state.markScheduled(index: 1, attempt: 1, lastErrorMessage: "first")
        _ = state.markScheduled(index: 2, attempt: 3, lastErrorMessage: "second")

        let stillRetrying = state.clear(index: 1)

        XCTAssertTrue(stillRetrying.isRetrying)
        XCTAssertEqual(stillRetrying.retryAttempt, 3)
        XCTAssertEqual(stillRetrying.retryLastError, "second")

        let cleared = state.clear(index: 2)
        XCTAssertFalse(cleared.isRetrying)
        XCTAssertEqual(cleared.retryAttempt, 0)
        XCTAssertNil(cleared.retryLastError)
    }

    func testResetClearsAllRetryState() {
        var state = TTSRequestRetryState()
        _ = state.markScheduled(index: 4, attempt: 2, lastErrorMessage: "failed")

        let published = state.reset()

        XCTAssertFalse(published.isRetrying)
        XCTAssertEqual(published.retryAttempt, 0)
        XCTAssertNil(published.retryLastError)
        XCTAssertEqual(state.nextAttempt(for: 4), 1)
    }
}
