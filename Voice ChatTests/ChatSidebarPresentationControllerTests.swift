import XCTest
@testable import Voice_Chat

final class ChatSidebarPresentationControllerTests: XCTestCase {
    func testSearchMatchesFoldedTitleAndActiveMessageBody() {
        var controller = ChatSidebarPresentationController()
        let titleMatch = makeSession(
            title: "Café Plan",
            messages: [
                ChatMessage(content: "ordinary message", isUser: true, createdAt: Date(timeIntervalSince1970: 1))
            ]
        )
        let bodyMatch = makeSession(
            title: "Notes",
            messages: [
                ChatMessage(content: "The needle is in the body", isUser: false, createdAt: Date(timeIntervalSince1970: 2))
            ]
        )
        let miss = makeSession(
            title: "Other",
            messages: [
                ChatMessage(content: "unrelated", isUser: false, createdAt: Date(timeIntervalSince1970: 3))
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
                    createdAt: Date(timeIntervalSince1970: 4)
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
        let message = ChatMessage(content: body, isUser: false, createdAt: Date(timeIntervalSince1970: 5))
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
