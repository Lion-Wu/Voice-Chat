import XCTest
@testable import Voice_Chat

final class ChatRequestActivityStateTests: XCTestCase {
    func testMarkActiveTracksPendingParentAndClearsAssistantIDs() throws {
        let parentID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        var state = ChatRequestActivityState(
            isLoading: false,
            isPriming: false,
            sending: false,
            currentAssistantMessageID: UUID(),
            interruptedAssistantMessageID: UUID(),
            pendingAssistantParentMessageID: nil
        )

        state.markActive(pendingParentMessageID: parentID)

        XCTAssertTrue(state.isLoading)
        XCTAssertTrue(state.isPriming)
        XCTAssertTrue(state.sending)
        XCTAssertTrue(state.hasActiveTextRequest)
        XCTAssertNil(state.currentAssistantMessageID)
        XCTAssertNil(state.interruptedAssistantMessageID)
        XCTAssertEqual(state.pendingAssistantParentMessageID, parentID)
    }

    func testInactiveAndClearTrackingOnlyOwnRequestActivityFields() {
        var state = ChatRequestActivityState(
            isLoading: true,
            isPriming: true,
            sending: true,
            currentAssistantMessageID: UUID(),
            interruptedAssistantMessageID: UUID(),
            pendingAssistantParentMessageID: UUID()
        )

        state.markInactive()

        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.isPriming)
        XCTAssertFalse(state.sending)
        XCTAssertFalse(state.hasActiveTextRequest)
        XCTAssertNotNil(state.currentAssistantMessageID)
        XCTAssertNotNil(state.interruptedAssistantMessageID)
        XCTAssertNotNil(state.pendingAssistantParentMessageID)

        state.clearAssistantTracking()

        XCTAssertNil(state.currentAssistantMessageID)
        XCTAssertNil(state.interruptedAssistantMessageID)
        XCTAssertNil(state.pendingAssistantParentMessageID)
    }

    func testRetryAndDeltaTransitionsPreserveAssistantIdentity() {
        let assistantID = UUID()
        var state = ChatRequestActivityState(
            isLoading: false,
            isPriming: false,
            sending: false,
            currentAssistantMessageID: assistantID,
            interruptedAssistantMessageID: nil,
            pendingAssistantParentMessageID: nil
        )

        state.keepActiveForRetry()

        XCTAssertTrue(state.isLoading)
        XCTAssertFalse(state.isPriming)
        XCTAssertTrue(state.sending)
        XCTAssertEqual(state.currentAssistantMessageID, assistantID)

        state.markAssistantDeltaStarted()

        XCTAssertTrue(state.isLoading)
        XCTAssertFalse(state.isPriming)
        XCTAssertEqual(state.currentAssistantMessageID, assistantID)
    }
}
