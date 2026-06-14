import XCTest
@testable import Voice_Chat

@MainActor
final class ChatQueuedDraftAutostartControllerTests: XCTestCase {
    func testScheduleSendsAfterYieldAndReportsCompletion() async {
        let controller = ChatQueuedDraftAutostartController()
        let recorder = QueuedDraftAutostartRecorder()
        let draft = QueuedChatDraft(id: uuid(81), text: "next")

        controller.schedule(
            decision: .start(draft),
            canStart: { _ in true },
            send: recorder.send(_:),
            complete: recorder.complete(id:didSend:)
        )

        await recorder.waitForCompletion()

        XCTAssertEqual(recorder.sentDraftIDs, [draft.id])
        XCTAssertEqual(recorder.completedIDs, [draft.id])
        XCTAssertEqual(recorder.completedSendResults, [true])
        XCTAssertFalse(controller.isScheduled)
    }

    func testCancelPreventsScheduledSend() async {
        let controller = ChatQueuedDraftAutostartController()
        let recorder = QueuedDraftAutostartRecorder()
        let draft = QueuedChatDraft(id: uuid(82), text: "next")

        controller.schedule(
            decision: .start(draft),
            canStart: { _ in true },
            send: recorder.send(_:),
            complete: recorder.complete(id:didSend:)
        )
        controller.cancel()

        await Task.yield()

        XCTAssertTrue(recorder.sentDraftIDs.isEmpty)
        XCTAssertTrue(recorder.completedIDs.isEmpty)
        XCTAssertFalse(controller.isScheduled)
    }
}

@MainActor
private final class QueuedDraftAutostartRecorder {
    private(set) var sentDraftIDs: [UUID] = []
    private(set) var completedIDs: [UUID] = []
    private(set) var completedSendResults: [Bool] = []

    func send(_ draft: QueuedChatDraft) -> Bool {
        sentDraftIDs.append(draft.id)
        return true
    }

    func complete(id: UUID, didSend: Bool) {
        completedIDs.append(id)
        completedSendResults.append(didSend)
    }

    func waitForCompletion() async {
        for _ in 0..<100 where completedIDs.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
