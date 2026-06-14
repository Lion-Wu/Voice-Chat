import XCTest
@testable import Voice_Chat

@MainActor
final class ChatBranchRestartCoordinatorTests: XCTestCase {
    func testPrepareRestartDetachesActiveChildAndRestoresIfAssistantNeverStarted() {
        let parent = ChatMessage(content: "prompt", isUser: true)
        let previousChildID = UUID()
        parent.activeChildMessageID = previousChildID
        let coordinator = ChatBranchRestartCoordinator()

        let restart = coordinator.prepareRestart(from: parent)

        XCTAssertEqual(restart.parentMessageID, parent.id)
        XCTAssertTrue(restart.didMutateBranch)
        XCTAssertNil(parent.activeChildMessageID)

        let restore = coordinator.restorePendingBranchIfAssistantDidNotStart(
            currentAssistantMessageID: nil,
            messageLookup: [parent.id: parent]
        )

        XCTAssertTrue(restore.didRestoreBranch)
        XCTAssertEqual(parent.activeChildMessageID, previousChildID)
    }

    func testRestoreDoesNothingAfterAssistantStartedAndClearDropsPendingRestore() {
        let parent = ChatMessage(content: "prompt", isUser: true)
        let previousChildID = UUID()
        parent.activeChildMessageID = previousChildID
        let coordinator = ChatBranchRestartCoordinator()

        _ = coordinator.prepareRestart(from: parent)

        let blocked = coordinator.restorePendingBranchIfAssistantDidNotStart(
            currentAssistantMessageID: UUID(),
            messageLookup: [parent.id: parent]
        )

        XCTAssertFalse(blocked.didRestoreBranch)
        XCTAssertNil(parent.activeChildMessageID)

        coordinator.clearPendingRestore()
        let afterClear = coordinator.restorePendingBranchIfAssistantDidNotStart(
            currentAssistantMessageID: nil,
            messageLookup: [parent.id: parent]
        )

        XCTAssertFalse(afterClear.didRestoreBranch)
        XCTAssertNil(parent.activeChildMessageID)
    }
}
