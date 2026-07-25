import XCTest
@testable import Voice_Chat

@MainActor
final class ChatVisibleMessageControllerTests: XCTestCase {
    func testHydratingRefreshPublishesVisibleMessagesAndFingerprints() async {
        let controller = ChatVisibleMessageController()
        let sessionID = uuid(71)
        let first = chatMessage(id: uuid(72), content: "first")
        let editingBase = chatMessage(id: uuid(73), content: "editing")
        let hidden = chatMessage(id: uuid(74), content: "hidden")
        let reporter = VisibleMessageCountReporter()

        controller.refreshVisibleMessages(
            orderedMessages: [first, editingBase, hidden],
            editingBaseMessageID: editingBase.id,
            sessionID: sessionID,
            hydrating: true,
            onVisibleCountChange: reporter.append(_:)
        )

        await waitForVisibleMessageCount(1, in: controller)

        XCTAssertEqual(controller.visibleMessages.map(\.id), [first.id])
        XCTAssertEqual(controller.fingerprintCache[first.id], ContentFingerprint.make("first"))
        XCTAssertNil(controller.fingerprintCache[editingBase.id])
        XCTAssertNil(controller.fingerprintCache[hidden.id])
        XCTAssertEqual(reporter.counts, [1])
    }

    func testRefreshDefersWhileHydratingThenAppliesLatestMessages() async {
        let controller = ChatVisibleMessageController()
        let sessionID = uuid(75)
        let initial = chatMessage(id: uuid(76), content: "initial")
        let added = chatMessage(id: uuid(77), content: "added")
        let reporter = VisibleMessageCountReporter()

        controller.refreshVisibleMessages(
            orderedMessages: [initial],
            editingBaseMessageID: nil,
            sessionID: sessionID,
            hydrating: true,
            onVisibleCountChange: reporter.append(_:)
        )
        controller.refreshVisibleMessages(
            orderedMessages: [initial, added],
            editingBaseMessageID: nil,
            sessionID: sessionID,
            onVisibleCountChange: reporter.append(_:)
        )

        await waitForVisibleMessageCount(2, in: controller)

        XCTAssertEqual(controller.visibleMessages.map(\.id), [initial.id, added.id])
        XCTAssertEqual(controller.fingerprintCache[initial.id], ContentFingerprint.make("initial"))
        XCTAssertEqual(controller.fingerprintCache[added.id], ContentFingerprint.make("added"))
        XCTAssertEqual(reporter.counts, [2])
    }

    private func waitForVisibleMessageCount(_ expectedCount: Int, in controller: ChatVisibleMessageController) async {
        for _ in 0..<200 where controller.isHydratingSession || controller.visibleMessages.count != expectedCount {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

@MainActor
final class ChatInitialRenderCoordinatorTests: XCTestCase {
    func testWaitsForEveryRegisteredMarkdownView() {
        let coordinator = ChatInitialRenderCoordinator()
        let first = NSObject()
        let second = NSObject()

        coordinator.begin()
        coordinator.register(first)
        coordinator.register(second)
        coordinator.finishCollecting()

        coordinator.markRendered(first)
        XCTAssertFalse(coordinator.isReady)

        coordinator.markRendered(second)
        XCTAssertFalse(coordinator.isReady)

        coordinator.contentDidLayout()
        XCTAssertTrue(coordinator.isReady)
    }

    func testCanFinishAfterMarkdownWasLaidOutDuringHydration() {
        let coordinator = ChatInitialRenderCoordinator()
        let renderer = NSObject()

        coordinator.begin()
        coordinator.register(renderer)
        coordinator.markRendered(renderer)
        coordinator.contentDidLayout()
        XCTAssertFalse(coordinator.isReady)

        coordinator.finishCollecting()
        XCTAssertTrue(coordinator.isReady)
    }

    func testDoesNotTrackMessagesAddedAfterPresentation() {
        let coordinator = ChatInitialRenderCoordinator()
        let streamingRenderer = NSObject()

        coordinator.begin()
        coordinator.finishCollecting()
        XCTAssertTrue(coordinator.isReady)

        coordinator.register(streamingRenderer)
        XCTAssertTrue(coordinator.isReady)
    }

    func testCanWaitForMarkdownAgainAfterBranchTransition() {
        let coordinator = ChatInitialRenderCoordinator()
        let renderer = NSObject()

        coordinator.begin()
        coordinator.finishCollecting()
        XCTAssertTrue(coordinator.isReady)

        coordinator.begin()
        coordinator.register(renderer)
        coordinator.finishCollecting()
        coordinator.markRendered(renderer)
        XCTAssertFalse(coordinator.isReady)

        coordinator.contentDidLayout()
        XCTAssertTrue(coordinator.isReady)
    }
}

@MainActor
private final class VisibleMessageCountReporter {
    private(set) var counts: [Int] = []

    func append(_ count: Int) {
        counts.append(count)
    }
}
