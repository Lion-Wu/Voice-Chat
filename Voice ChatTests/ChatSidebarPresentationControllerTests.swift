import XCTest
@testable import Voice_Chat

final class ChatSidebarPresentationControllerTests: XCTestCase {
    func testSearchMatchesFoldedTitleAndActiveMessageBody() {
        var controller = ChatSidebarPresentationController()
        let titleMatch = makeSession(
            title: "Café Match",
            messages: [
                ChatMessage(
                    content: "Message without the body query",
                    isUser: true,
                    createdAt: TestDate.reference
                )
            ]
        )
        let bodyMatch = makeSession(
            title: "Body Match",
            messages: [
                ChatMessage(
                    content: "This message contains the needle query",
                    isUser: false,
                    createdAt: TestDate.offset(1)
                )
            ]
        )
        let miss = makeSession(
            title: "Nonmatching Conversation",
            messages: [
                ChatMessage(
                    content: "Message without either search query",
                    isUser: false,
                    createdAt: TestDate.offset(2)
                )
            ]
        )

        XCTAssertEqual(controller.normalizedQuery("  CAFÉ  "), "cafe")
        XCTAssertEqual(controller.sessions(matching: "cafe", in: [titleMatch, bodyMatch, miss]).map(\.id), [titleMatch.id])
        XCTAssertEqual(controller.sessions(matching: "needle", in: [titleMatch, bodyMatch, miss]).map(\.id), [bodyMatch.id])
    }

    func testPreviewBuildsContextAndEmphasizedRanges() {
        var controller = ChatSidebarPresentationController()
        let session = makeSession(
            title: "Search",
            messages: [
                ChatMessage(
                    content: "alpha beta gamma needle delta epsilon zeta eta theta",
                    isUser: false,
                    createdAt: TestDate.reference
                )
            ]
        )

        let preview = controller.preview(for: session, matchingSearchQuery: "needle")

        XCTAssertTrue(preview.text.contains("needle"))
        XCTAssertFalse(preview.emphasizedRanges.isEmpty)
        let nsPreview = preview.text as NSString
        XCTAssertEqual(nsPreview.substring(with: preview.emphasizedRanges[0]), "needle")
    }

    func testBodySearchMatchIgnoresThinkPartsAndComputesLineAnchor() throws {
        var controller = ChatSidebarPresentationController()
        let body = "<think>\nhidden needle\n</think>\none\ntwo\nthree\nfour\nneedle five"
        let message = ChatMessage(content: body, isUser: false, createdAt: TestDate.reference)
        let session = makeSession(title: "Anchors", messages: [message])
        let normalized = controller.normalizedQuery("needle")

        let match = try XCTUnwrap(controller.bodySearchMatch(
            in: session,
            rawQuery: "needle",
            matchingNormalizedQuery: normalized
        ))

        XCTAssertEqual(match.messageID, message.id)
        XCTAssertFalse(match.bodyText.contains("hidden needle"))
        XCTAssertEqual(match.anchorY, 0.9, accuracy: 0.001)
    }

    private func makeSession(title: String, messages: [ChatMessage]) -> ChatSession {
        let session = ChatSession(title: title)
        session.messages = messages
        session.lastMessageAt = messages.max(by: { $0.createdAt < $1.createdAt })?.createdAt
        return session
    }
}
