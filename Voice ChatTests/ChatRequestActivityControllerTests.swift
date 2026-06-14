import XCTest
@testable import Voice_Chat

@MainActor
final class ChatRequestActivityControllerTests: XCTestCase {
    func testPublishesOnlyLoadingAndPrimingTransitions() {
        let controller = ChatRequestActivityController()
        let parentID = UUID()
        var emissions: [ChatRequestActivityController.PublishedState] = []

        controller.onPublishedStateChange = { emissions.append($0) }

        controller.markActive(pendingParentMessageID: parentID)
        controller.currentAssistantMessageID = UUID()
        controller.markAssistantDeltaStarted()
        controller.markInactive()

        XCTAssertEqual(
            emissions,
            [
                .init(isLoading: true, isPriming: true),
                .init(isLoading: true, isPriming: false),
                .init(isLoading: false, isPriming: false)
            ]
        )
        XCTAssertEqual(controller.pendingAssistantParentMessageID, parentID)
    }

    func testClearAssistantTrackingDoesNotChangePublishedState() {
        let controller = ChatRequestActivityController()
        let assistantID = UUID()
        let interruptedID = UUID()
        let parentID = UUID()
        var emissionCount = 0

        controller.currentAssistantMessageID = assistantID
        controller.interruptedAssistantMessageID = interruptedID
        controller.pendingAssistantParentMessageID = parentID
        controller.onPublishedStateChange = { _ in emissionCount += 1 }

        controller.clearAssistantTracking()

        XCTAssertNil(controller.currentAssistantMessageID)
        XCTAssertNil(controller.interruptedAssistantMessageID)
        XCTAssertNil(controller.pendingAssistantParentMessageID)
        XCTAssertEqual(emissionCount, 0)
    }

    func testRetryKeepsRequestActiveAndPreservesKnownAssistant() {
        let controller = ChatRequestActivityController()
        let assistantID = UUID()
        var emissions: [ChatRequestActivityController.PublishedState] = []

        controller.currentAssistantMessageID = assistantID
        controller.onPublishedStateChange = { emissions.append($0) }

        controller.keepActiveForRetry()

        XCTAssertTrue(controller.sending)
        XCTAssertTrue(controller.hasActiveTextRequest)
        XCTAssertEqual(controller.currentAssistantMessageID, assistantID)
        XCTAssertEqual(emissions, [.init(isLoading: true, isPriming: false)])
    }
}
