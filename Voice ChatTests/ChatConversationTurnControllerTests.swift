import XCTest
@testable import Voice_Chat

@MainActor
final class ChatConversationTurnControllerTests: XCTestCase {
    func testAcceptedTurnPreparesBeforeAppendingUserMessage() {
        let session = ChatSession(title: "New Chat")
        let parent = ChatMessage(content: "previous", isUser: false)
        session.messages.append(parent)
        var events: [String] = []

        let result = ChatConversationTurnController.startTurn(
            draft: QueuedChatDraft(text: "  hello  "),
            session: session,
            hasActiveTextRequest: false,
            supportsImageInputs: true,
            hasImageInputContext: false,
            ignoringUnsupportedImageInputs: false,
            clearComposerAfterSend: true,
            prepareForAppend: {
                events.append("prepare")
            },
            fallbackParent: {
                events.append("parent")
                return parent
            },
            estimatedTokenCount: { $0 },
            createdAt: Date(timeIntervalSince1970: 10)
        )

        guard case let .accepted(turnStart) = result else {
            return XCTFail("Expected accepted turn")
        }
        XCTAssertEqual(events, ["prepare", "parent"])
        XCTAssertEqual(turnStart.userMessage.content, "hello")
        XCTAssertEqual(turnStart.userMessage.parentMessage?.id, parent.id)
        XCTAssertEqual(parent.activeChildMessageID, turnStart.userMessage.id)
        XCTAssertEqual(session.messages.last?.id, turnStart.userMessage.id)
        XCTAssertTrue(turnStart.shouldClearComposerAfterSend)
        XCTAssertFalse(turnStart.shouldClearEditingBaseMessageID)
    }

    func testRejectedTurnDoesNotPrepareOrAppend() {
        let session = ChatSession(title: "New Chat")
        var didPrepare = false

        let result = ChatConversationTurnController.startTurn(
            draft: QueuedChatDraft(text: "blocked"),
            session: session,
            hasActiveTextRequest: true,
            supportsImageInputs: true,
            hasImageInputContext: false,
            ignoringUnsupportedImageInputs: false,
            clearComposerAfterSend: true,
            prepareForAppend: {
                didPrepare = true
            },
            fallbackParent: { nil },
            estimatedTokenCount: { $0 }
        )

        guard case let .rejected(reason) = result else {
            return XCTFail("Expected rejected turn")
        }
        XCTAssertEqual(reason, .activeTextRequest)
        XCTAssertFalse(didPrepare)
        XCTAssertTrue(session.messages.isEmpty)
    }

    func testEditingBaseMessageClearsEditingStateWhenComposerWillClear() {
        let session = ChatSession(title: "Existing")
        let root = ChatMessage(content: "root", isUser: true)
        let edited = ChatMessage(content: "old", isUser: true)
        edited.parentMessage = root
        session.messages.append(root)
        session.messages.append(edited)

        let result = ChatConversationTurnController.startTurn(
            draft: QueuedChatDraft(text: "replacement", editingBaseMessageID: edited.id),
            session: session,
            hasActiveTextRequest: false,
            supportsImageInputs: true,
            hasImageInputContext: false,
            ignoringUnsupportedImageInputs: false,
            clearComposerAfterSend: true,
            fallbackParent: { nil },
            estimatedTokenCount: { _ in 1 }
        )

        guard case let .accepted(turnStart) = result else {
            return XCTFail("Expected accepted turn")
        }
        XCTAssertTrue(turnStart.shouldClearEditingBaseMessageID)
        XCTAssertEqual(turnStart.userMessage.parentMessage?.id, root.id)
        XCTAssertEqual(root.activeChildMessageID, turnStart.userMessage.id)
    }
}
