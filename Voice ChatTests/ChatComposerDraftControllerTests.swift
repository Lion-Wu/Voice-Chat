import XCTest
@testable import Voice_Chat

final class ChatComposerDraftControllerTests: XCTestCase {
    func testCurrentDraftIgnoresEmptyComposerAndKeepsEditingBase() {
        XCTAssertNil(ChatComposerDraftController.currentDraft(from: .empty))
        XCTAssertNil(ChatComposerDraftController.currentDraft(from: ChatComposerDraftState(text: "  \n  ")))

        let baseID = uuid(91)
        let draft = ChatComposerDraftController.currentDraft(
            from: ChatComposerDraftState(text: " revised ", editingBaseMessageID: baseID)
        )

        XCTAssertEqual(draft?.text, " revised ")
        XCTAssertEqual(draft?.editingBaseMessageID, baseID)
    }

    func testCurrentDraftAcceptsImageOnlyComposer() {
        let attachment = ChatImageAttachment(mimeType: "image/png", data: Data([1, 2, 3]))

        let draft = ChatComposerDraftController.currentDraft(
            from: ChatComposerDraftState(text: "  ", imageAttachments: [attachment])
        )

        XCTAssertEqual(draft?.imageAttachments, [attachment])
    }

    func testEditingStateOnlyUsesUserMessages() {
        let user = chatMessage(id: uuid(92), content: "edit me", isUser: true)
        let assistant = chatMessage(id: uuid(93), content: "no", isUser: false)

        XCTAssertEqual(
            ChatComposerDraftController.editingState(from: user),
            ChatComposerDraftState(text: "edit me", editingBaseMessageID: user.id)
        )
        XCTAssertNil(ChatComposerDraftController.editingState(from: assistant))
    }
}
