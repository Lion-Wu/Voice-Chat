import XCTest
@testable import Voice_Chat

final class ChatAssistantDeltaAppenderTests: XCTestCase {
    func testAssistantDeltaAppenderCreatesMessageUnderPendingParent() {
        let session = ChatSession()
        let parent = ChatMessage(content: "prompt", isUser: true)
        session.messages = [parent]

        let result = ChatAssistantDeltaAppender.append(
            piece: "hello",
            to: session,
            currentAssistantMessageID: nil,
            pendingAssistantParentMessageID: parent.id,
            streamingAssistantMessageID: nil,
            streamingAssistantFingerprint: nil,
            messageLookup: [parent.id: parent],
            fallbackParent: { nil },
            now: Date(timeIntervalSince1970: 10)
        )

        XCTAssertTrue(result.didCreateMessage)
        XCTAssertTrue(result.didResolvePendingAssistantParent)
        XCTAssertEqual(result.message.content, "hello")
        XCTAssertFalse(result.message.isUser)
        XCTAssertEqual(result.message.parentMessage?.id, parent.id)
        XCTAssertEqual(parent.activeChildMessageID, result.message.id)
        XCTAssertEqual(session.messages.map(\.id), [parent.id, result.message.id])
        XCTAssertEqual(result.fingerprint, ContentFingerprint.make("hello"))
    }

    func testAssistantDeltaAppenderAppendsExistingMessageWithStreamingFingerprint() {
        let session = ChatSession()
        let assistant = ChatMessage(content: "hel", isUser: false)
        session.messages = [assistant]
        let previousFingerprint = ContentFingerprint.make("hel")

        let result = ChatAssistantDeltaAppender.append(
            piece: "lo",
            to: session,
            currentAssistantMessageID: assistant.id,
            pendingAssistantParentMessageID: nil,
            streamingAssistantMessageID: assistant.id,
            streamingAssistantFingerprint: previousFingerprint,
            messageLookup: [assistant.id: assistant],
            fallbackParent: { nil },
            now: Date(timeIntervalSince1970: 11)
        )

        XCTAssertFalse(result.didCreateMessage)
        XCTAssertFalse(result.didResolvePendingAssistantParent)
        XCTAssertTrue(result.message === assistant)
        XCTAssertEqual(assistant.content, "hello")
        XCTAssertEqual(result.fingerprint, previousFingerprint.appending("lo"))
    }
}
