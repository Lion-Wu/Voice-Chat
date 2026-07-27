import Combine
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
        XCTAssertEqual(reporter.counts, [1, 2])
    }

    func testFingerprintUpdatePublishesOneAtomicSnapshotAndSkipsDuplicates() {
        let controller = ChatVisibleMessageController()
        let messageID = uuid(78)
        let fingerprint = ContentFingerprint.make("streaming")
        var publicationCount = 0
        let cancellable = controller.objectWillChange.sink {
            publicationCount += 1
        }

        controller.applyContentFingerprintUpdate(
            messageID: messageID,
            fingerprint: fingerprint
        )

        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(controller.fingerprintCache[messageID], fingerprint)

        controller.applyContentFingerprintUpdate(
            messageID: messageID,
            fingerprint: fingerprint
        )

        XCTAssertEqual(publicationCount, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testRefreshDuringFingerprintAwaitCompletesHydrationAndAppliesPendingRefresh() async {
        let gate = ControlledFingerprintGate()
        let controller = ChatVisibleMessageController(
            fingerprintBuilder: { snapshots in
                await gate.wait()
                return Dictionary(uniqueKeysWithValues: snapshots.map {
                    ($0.0, ContentFingerprint.make($0.1))
                })
            }
        )
        let sessionID = uuid(79)
        let initial = chatMessage(id: uuid(80), content: "initial")
        let added = chatMessage(id: uuid(81), content: "added")
        let reporter = VisibleMessageCountReporter()

        controller.refreshVisibleMessages(
            orderedMessages: [initial],
            editingBaseMessageID: nil,
            sessionID: sessionID,
            hydrating: true,
            onVisibleCountChange: reporter.append(_:)
        )
        await waitForFingerprintBuilderStart(gate)

        controller.refreshVisibleMessages(
            orderedMessages: [initial, added],
            editingBaseMessageID: nil,
            sessionID: sessionID,
            onVisibleCountChange: reporter.append(_:)
        )

        XCTAssertTrue(controller.isHydratingSession)
        await gate.open()
        await waitForVisibleMessageCount(2, in: controller)

        XCTAssertFalse(controller.isHydratingSession)
        XCTAssertEqual(controller.visibleMessages.map(\.id), [initial.id, added.id])
        XCTAssertEqual(controller.fingerprintCache[added.id], ContentFingerprint.make("added"))
        XCTAssertEqual(reporter.counts, [1, 2])
    }

    func testCancelledHydrationCannotPublishOverReplacementHydration() async {
        let gate = ControlledFingerprintGate()
        let controller = ChatVisibleMessageController(
            fingerprintBuilder: { snapshots in
                await gate.wait()
                return Dictionary(uniqueKeysWithValues: snapshots.map {
                    ($0.0, ContentFingerprint.make($0.1))
                })
            }
        )
        let sessionID = uuid(82)
        let stale = chatMessage(id: uuid(83), content: "stale")
        let stalePending = chatMessage(id: uuid(90), content: "stale pending")
        let replacement = chatMessage(id: uuid(84), content: "replacement")
        let reporter = VisibleMessageCountReporter()

        controller.refreshVisibleMessages(
            orderedMessages: [stale],
            editingBaseMessageID: nil,
            sessionID: sessionID,
            hydrating: true,
            onVisibleCountChange: reporter.append(_:)
        )
        await waitForFingerprintBuilderStart(gate)
        controller.refreshVisibleMessages(
            orderedMessages: [stale, stalePending],
            editingBaseMessageID: nil,
            sessionID: sessionID,
            onVisibleCountChange: reporter.append(_:)
        )

        controller.cancelHydration()
        controller.refreshVisibleMessages(
            orderedMessages: [replacement],
            editingBaseMessageID: nil,
            sessionID: sessionID,
            hydrating: true,
            onVisibleCountChange: reporter.append(_:)
        )
        controller.applyContentFingerprintUpdate(
            messageID: replacement.id,
            fingerprint: ContentFingerprint.make(replacement.content)
        )
        await gate.open()
        await waitForVisibleMessageCount(1, in: controller)
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertFalse(controller.isHydratingSession)
        XCTAssertEqual(controller.visibleMessages.map(\.id), [replacement.id])
        XCTAssertNil(controller.fingerprintCache[stale.id])
        XCTAssertNil(controller.fingerprintCache[stalePending.id])
        XCTAssertEqual(
            controller.fingerprintCache[replacement.id],
            ContentFingerprint.make("replacement")
        )
    }

    func testReplacementHydrationDiscardsPendingRefreshOwnedByPreviousGeneration() async {
        let gate = ControlledFingerprintGate()
        let controller = ChatVisibleMessageController(
            fingerprintBuilder: { snapshots in
                await gate.wait()
                return Dictionary(uniqueKeysWithValues: snapshots.map {
                    ($0.0, ContentFingerprint.make($0.1))
                })
            }
        )
        let staleSessionID = uuid(85)
        let replacementSessionID = uuid(86)
        let stale = chatMessage(id: uuid(87), content: "stale")
        let stalePending = chatMessage(id: uuid(88), content: "stale pending")
        let replacement = chatMessage(id: uuid(89), content: "replacement")
        let reporter = VisibleMessageCountReporter()

        controller.refreshVisibleMessages(
            orderedMessages: [stale],
            editingBaseMessageID: nil,
            sessionID: staleSessionID,
            hydrating: true,
            onVisibleCountChange: reporter.append(_:)
        )
        await waitForFingerprintBuilderStart(gate)
        controller.refreshVisibleMessages(
            orderedMessages: [stale, stalePending],
            editingBaseMessageID: nil,
            sessionID: staleSessionID,
            onVisibleCountChange: reporter.append(_:)
        )

        controller.refreshVisibleMessages(
            orderedMessages: [replacement],
            editingBaseMessageID: nil,
            sessionID: replacementSessionID,
            hydrating: true,
            onVisibleCountChange: reporter.append(_:)
        )
        await gate.open()
        await waitForVisibleMessageCount(1, in: controller)

        XCTAssertFalse(controller.isHydratingSession)
        XCTAssertEqual(controller.visibleMessages.map(\.id), [replacement.id])
        XCTAssertNil(controller.fingerprintCache[stale.id])
        XCTAssertNil(controller.fingerprintCache[stalePending.id])
        XCTAssertEqual(
            controller.fingerprintCache[replacement.id],
            ContentFingerprint.make("replacement")
        )
    }

    private func waitForFingerprintBuilderStart(_ gate: ControlledFingerprintGate) async {
        for _ in 0..<200 {
            if await gate.hasWaiter {
                return
            }
            await Task.yield()
        }
        XCTFail("Fingerprint builder did not start")
    }

    private func waitForVisibleMessageCount(_ expectedCount: Int, in controller: ChatVisibleMessageController) async {
        for _ in 0..<200 where controller.isHydratingSession || controller.visibleMessages.count != expectedCount {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

@MainActor
final class ChatInitialRenderCoordinatorTests: XCTestCase {
    func testRendererCompletesWithoutFutureAggregateHeightChange() {
        let coordinator = ChatInitialRenderCoordinator()
        let renderer = NSObject()
        let generation = coordinator.generation

        XCTAssertTrue(coordinator.register(renderer, generation: generation))
        coordinator.finishCollecting()

        XCTAssertFalse(coordinator.isReady)
        coordinator.markRendered(renderer, generation: generation)
        XCTAssertFalse(coordinator.isReady)

        coordinator.markLaidOut(renderer, generation: generation)
        XCTAssertTrue(coordinator.isReady)
    }

    func testViewAppearanceRestartsGateAfterPrematureFinish() {
        let coordinator = ChatInitialRenderCoordinator()
        let renderer = NSObject()
        let prematureGeneration = coordinator.generation

        coordinator.finishCollecting(generation: prematureGeneration)

        XCTAssertTrue(coordinator.isReady)

        coordinator.begin()
        let appearanceGeneration = coordinator.generation

        XCTAssertNotEqual(appearanceGeneration, prematureGeneration)
        XCTAssertFalse(coordinator.isReady)
        XCTAssertTrue(coordinator.register(
            renderer,
            generation: appearanceGeneration
        ))

        coordinator.finishCollecting(generation: prematureGeneration)

        XCTAssertFalse(coordinator.isReady)

        coordinator.finishCollecting(generation: appearanceGeneration)

        XCTAssertFalse(coordinator.isReady)

        coordinator.markRendered(renderer, generation: appearanceGeneration)

        XCTAssertFalse(coordinator.isReady)

        coordinator.markLaidOut(renderer, generation: appearanceGeneration)

        XCTAssertTrue(coordinator.isReady)
    }

    func testAcceptsRendererLayoutBeforeRenderCallback() {
        let coordinator = ChatInitialRenderCoordinator()
        let renderer = NSObject()
        let generation = coordinator.generation

        coordinator.register(renderer, generation: generation)
        coordinator.markLaidOut(renderer, generation: generation)
        coordinator.finishCollecting(generation: generation)

        XCTAssertFalse(coordinator.isReady)

        coordinator.markRendered(renderer, generation: generation)

        XCTAssertTrue(coordinator.isReady)
    }

    func testWaitsForEveryRegisteredMarkdownView() {
        let coordinator = ChatInitialRenderCoordinator()
        let first = NSObject()
        let second = NSObject()

        coordinator.begin()
        let generation = coordinator.generation
        coordinator.register(first, generation: generation)
        coordinator.register(second, generation: generation)
        coordinator.finishCollecting(generation: generation)

        coordinator.markRendered(first, generation: generation)
        coordinator.markLaidOut(first, generation: generation)
        XCTAssertFalse(coordinator.isReady)

        coordinator.markRendered(second, generation: generation)
        XCTAssertFalse(coordinator.isReady)

        coordinator.markLaidOut(second, generation: generation)
        XCTAssertTrue(coordinator.isReady)
    }

    func testCanFinishAfterMarkdownWasLaidOutDuringHydration() {
        let coordinator = ChatInitialRenderCoordinator()
        let renderer = NSObject()

        coordinator.begin()
        let generation = coordinator.generation
        coordinator.register(renderer, generation: generation)
        coordinator.markRendered(renderer, generation: generation)
        coordinator.markLaidOut(renderer, generation: generation)
        XCTAssertFalse(coordinator.isReady)

        coordinator.finishCollecting(generation: generation)
        XCTAssertTrue(coordinator.isReady)
    }

    func testDoesNotTrackMessagesAddedAfterPresentation() {
        let coordinator = ChatInitialRenderCoordinator()
        let streamingRenderer = NSObject()

        coordinator.begin()
        coordinator.finishCollecting()
        XCTAssertTrue(coordinator.isReady)

        XCTAssertFalse(coordinator.register(
            streamingRenderer,
            generation: coordinator.generation
        ))
        XCTAssertTrue(coordinator.isReady)
    }

    func testIgnoresLateCallbacksFromPreviousPresentation() {
        let coordinator = ChatInitialRenderCoordinator()
        let staleRenderer = NSObject()
        let currentRenderer = NSObject()
        let staleGeneration = coordinator.generation

        coordinator.register(staleRenderer, generation: staleGeneration)

        coordinator.begin()
        let currentGeneration = coordinator.generation
        coordinator.register(currentRenderer, generation: currentGeneration)
        coordinator.finishCollecting(generation: currentGeneration)

        coordinator.markRendered(staleRenderer, generation: staleGeneration)
        coordinator.markLaidOut(staleRenderer, generation: staleGeneration)
        XCTAssertFalse(coordinator.isReady)

        coordinator.markRendered(currentRenderer, generation: currentGeneration)
        coordinator.markLaidOut(currentRenderer, generation: currentGeneration)
        XCTAssertTrue(coordinator.isReady)
    }

    func testSameRendererCanRegisterForANewPresentationGeneration() {
        let coordinator = ChatInitialRenderCoordinator()
        let renderer = NSObject()
        let firstGeneration = coordinator.generation

        coordinator.register(renderer, generation: firstGeneration)
        coordinator.markRendered(renderer, generation: firstGeneration)
        coordinator.markLaidOut(renderer, generation: firstGeneration)
        coordinator.finishCollecting(generation: firstGeneration)
        XCTAssertTrue(coordinator.isReady)

        coordinator.begin()
        let nextGeneration = coordinator.generation
        XCTAssertTrue(coordinator.register(renderer, generation: nextGeneration))
        coordinator.markRendered(renderer, generation: nextGeneration)
        coordinator.markLaidOut(renderer, generation: nextGeneration)
        coordinator.finishCollecting(generation: nextGeneration)

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

private actor ControlledFingerprintGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var hasWaiter: Bool {
        !waiters.isEmpty
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
