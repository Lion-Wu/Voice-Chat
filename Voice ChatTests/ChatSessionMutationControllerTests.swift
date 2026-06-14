import Combine
import XCTest
@testable import Voice_Chat

@MainActor
final class ChatSessionMutationControllerTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    func testPersistSessionTracksAndPersistsSession() {
        let persistence = ChatSessionPersistenceSpy()
        let controller = ChatSessionMutationController(
            sessionPersistence: persistence,
            branchDidChange: PassthroughSubject<Void, Never>()
        )
        let session = ChatSession(title: "Test")

        controller.persistSession(session, reason: .immediate)

        XCTAssertEqual(persistence.trackedSessionIDs, [session.id])
        XCTAssertEqual(persistence.persistedSessionIDs, [session.id])
        XCTAssertEqual(persistence.persistReasons.count, 1)
        XCTAssertImmediate(persistence.persistReasons.first)
    }

    func testMessageTreeRepairPublishesBranchChangeAndPersists() {
        let persistence = ChatSessionPersistenceSpy()
        let branchDidChange = PassthroughSubject<Void, Never>()
        let controller = ChatSessionMutationController(
            sessionPersistence: persistence,
            branchDidChange: branchDidChange
        )
        var branchChangeCount = 0
        branchDidChange
            .sink { branchChangeCount += 1 }
            .store(in: &cancellables)

        let session = ChatSession(title: "Branched")
        let root = ChatMessage(
            content: "root",
            isUser: true,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let child = ChatMessage(
            content: "child",
            isUser: false,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let leaf = ChatMessage(
            content: "leaf",
            isUser: true,
            createdAt: Date(timeIntervalSince1970: 3)
        )
        child.parentMessage = root
        leaf.parentMessage = child
        root.activeChildMessageID = UUID()
        child.activeChildMessageID = leaf.id
        leaf.activeChildMessageID = UUID()
        session.messages = [leaf, child, root]
        session.activeRootMessageID = child.id

        let didRepair = controller.repairMessageTreeIfNeeded(
            in: session,
            isSending: false,
            finalizeDanglingActiveAssistantMessages: { false }
        )
        let branch = controller.activeBranchMessages(in: session)

        XCTAssertTrue(didRepair)
        XCTAssertEqual(branch.map(\.id), [root.id, child.id, leaf.id])
        XCTAssertEqual(session.activeRootMessageID, root.id)
        XCTAssertEqual(root.activeChildMessageID, child.id)
        XCTAssertEqual(child.activeChildMessageID, leaf.id)
        XCTAssertNil(leaf.activeChildMessageID)
        XCTAssertEqual(branchChangeCount, 1)
        XCTAssertEqual(persistence.persistReasons.count, 1)
        XCTAssertImmediate(persistence.persistReasons.first)
    }

    private func XCTAssertImmediate(
        _ reason: SessionPersistReason?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .immediate? = reason else {
            return XCTFail("Expected immediate persist reason", file: file, line: line)
        }
    }
}

@MainActor
private final class ChatSessionPersistenceSpy: ChatSessionPersisting, ChatSessionActivityPublishing {
    private(set) var trackedSessionIDs: [UUID] = []
    private(set) var persistedSessionIDs: [UUID] = []
    private(set) var persistReasons: [SessionPersistReason] = []

    func ensureSessionTracked(_ session: ChatSession) {
        trackedSessionIDs.append(session.id)
    }

    func persist(session: ChatSession, reason: SessionPersistReason) -> Bool {
        persistedSessionIDs.append(session.id)
        persistReasons.append(reason)
        return true
    }

    func flushPendingSaves() {}

    func publishLiveActivity(for session: ChatSession) {}
}
