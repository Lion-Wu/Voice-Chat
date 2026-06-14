import XCTest
@testable import Voice_Chat

final class ChatQueuedDraftCoordinatorTests: XCTestCase {
    func testUnsupportedImagePolicyUsesDraftImagesAndBranchContext() {
        let attachment = ChatImageAttachment(mimeType: "image/png", data: Data([1, 2, 3]))
        let textDraft = QueuedChatDraft(text: "continue")
        let imageDraft = QueuedChatDraft(text: "", imageAttachments: [attachment])

        XCTAssertFalse(ChatQueuedDraftUnsupportedImagePolicy(
            supportsImageInputs: true,
            activeBranchContainsImageInputs: true
        ).shouldWarn(about: imageDraft))

        XCTAssertTrue(ChatQueuedDraftUnsupportedImagePolicy(
            supportsImageInputs: false,
            activeBranchContainsImageInputs: false
        ).shouldWarn(about: imageDraft))

        XCTAssertTrue(ChatQueuedDraftUnsupportedImagePolicy(
            supportsImageInputs: false,
            activeBranchContainsImageInputs: true
        ).shouldWarn(about: textDraft))

        XCTAssertFalse(ChatQueuedDraftUnsupportedImagePolicy(
            supportsImageInputs: false,
            activeBranchContainsImageInputs: false
        ).shouldWarn(about: QueuedChatDraft(text: "")))
    }

    func testCoordinatorControlsUnsupportedConfirmationAndManualSendRemoval() throws {
        let draftID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000031"))
        let attachment = ChatImageAttachment(mimeType: "image/png", data: Data([1, 2, 3]))
        let draft = QueuedChatDraft(id: draftID, text: "caption", imageAttachments: [attachment])
        let unsupportedPolicy = ChatQueuedDraftUnsupportedImagePolicy(
            supportsImageInputs: false,
            activeBranchContainsImageInputs: false
        )
        var coordinator = ChatQueuedDraftCoordinator()

        coordinator.enqueue(draft)
        coordinator.requestUnsupportedImageConfirmation(for: draftID, policy: unsupportedPolicy)

        XCTAssertEqual(coordinator.pendingUnsupportedImageDraftID, draftID)
        XCTAssertEqual(
            coordinator.prepareManualSend(
                id: draftID,
                ignoringUnsupportedImageInputs: false,
                policy: unsupportedPolicy
            ),
            .needsUnsupportedImageConfirmation(draftID)
        )

        let sendDecision = coordinator.prepareManualSend(
            id: draftID,
            ignoringUnsupportedImageInputs: true,
            policy: unsupportedPolicy
        )
        XCTAssertEqual(sendDecision, .send(draft))
        XCTAssertNil(coordinator.pendingUnsupportedImageDraftID)

        coordinator.removeAfterSend(id: draftID, didSend: true)

        XCTAssertFalse(coordinator.hasDrafts)
    }

    func testCoordinatorPlansAutostartWithoutOwningAsyncTask() throws {
        let draftID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000041"))
        let draft = QueuedChatDraft(id: draftID, text: "next")
        let supportedPolicy = ChatQueuedDraftUnsupportedImagePolicy(
            supportsImageInputs: true,
            activeBranchContainsImageInputs: false
        )
        var coordinator = ChatQueuedDraftCoordinator()

        coordinator.enqueue(draft)

        XCTAssertEqual(
            coordinator.prepareAutostart(hasActiveTextRequest: true, policy: supportedPolicy),
            .blockedByActiveRequest
        )
        XCTAssertEqual(
            coordinator.prepareAutostart(hasActiveTextRequest: false, policy: supportedPolicy),
            .start(draft)
        )

        coordinator.removeAutostartedDraft(id: draftID, didSend: false)
        XCTAssertTrue(coordinator.hasDrafts)

        coordinator.removeAutostartedDraft(id: draftID, didSend: true)
        XCTAssertFalse(coordinator.hasDrafts)
    }
}
