import XCTest
@testable import Voice_Chat

@MainActor
final class ChatStreamRetryStatusControllerTests: XCTestCase {
    func testPlanRetryPublishesRetryStateAndClearsAfterProgress() {
        let controller = ChatStreamRetryStatusController()
        var emissions: [ChatStreamRetryStatusController.PublishedState] = []
        controller.onPublishedStateChange = { emissions.append($0) }

        let plan = controller.planRetry(
            after: URLError(.timedOut),
            errorText: "Request timed out",
            hasAssistantMessage: false
        )

        XCTAssertTrue(plan.state.isRetrying)
        XCTAssertEqual(plan.state.retryAttempt, 1)
        XCTAssertEqual(plan.state.retryLastError, "Request timed out")
        XCTAssertEqual(
            emissions,
            [
                .init(
                    isRetrying: true,
                    retryAttempt: 1,
                    retryLastError: "Request timed out"
                )
            ]
        )

        controller.clearStateAfterProgressIfNeeded()

        XCTAssertEqual(
            emissions.last,
            .init(isRetrying: false, retryAttempt: 0, retryLastError: nil)
        )
    }

    func testResetDoesNotPublishWhenAlreadyIdle() {
        let controller = ChatStreamRetryStatusController()
        var emissionCount = 0
        controller.onPublishedStateChange = { _ in emissionCount += 1 }

        controller.reset()

        XCTAssertEqual(emissionCount, 0)
    }

    func testShouldAutoRetryUsesCurrentAttemptState() {
        let controller = ChatStreamRetryStatusController(
            state: ChatStreamRetryState(
                isRetrying: true,
                retryAttempt: 2,
                retryLastError: "timeout"
            )
        )

        XCTAssertFalse(controller.shouldAutoRetry(after: URLError(.timedOut)))
    }
}
