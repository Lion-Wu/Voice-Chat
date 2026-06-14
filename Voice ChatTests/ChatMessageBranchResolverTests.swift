import XCTest
@testable import Voice_Chat

final class ChatMessageBranchResolverTests: XCTestCase {
    func testChatMessageBranchResolverFallsBackToNewestChildForInvalidActiveChild() {
        let session = ChatSession()
        let root = chatMessage(
            id: uuid(1),
            content: "root",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let olderChild = chatMessage(
            id: uuid(2),
            content: "older child",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let newerChild = chatMessage(
            id: uuid(3),
            content: "newer child",
            createdAt: Date(timeIntervalSince1970: 3)
        )
        olderChild.parentMessage = root
        newerChild.parentMessage = root
        root.activeChildMessageID = uuid(99)
        session.messages = [newerChild, root, olderChild]
        session.activeRootMessageID = root.id

        let resolution = ChatMessageBranchResolver.activeBranchMessages(in: session)

        XCTAssertEqual(resolution.messages.map(\.id), [root.id, newerChild.id])
        XCTAssertFalse(resolution.didMutate)
        XCTAssertFalse(resolution.didMutateBranch)
    }

    func testChatMessageBranchResolverRepairsActiveRootAndChildPointers() {
        let session = ChatSession()
        let root = chatMessage(
            id: uuid(11),
            content: "root",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let child = chatMessage(
            id: uuid(12),
            content: "child",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let leaf = chatMessage(
            id: uuid(13),
            content: "leaf",
            createdAt: Date(timeIntervalSince1970: 3)
        )
        child.parentMessage = root
        leaf.parentMessage = child
        root.activeChildMessageID = uuid(98)
        child.activeChildMessageID = leaf.id
        leaf.activeChildMessageID = uuid(97)
        session.messages = [leaf, child, root]
        session.activeRootMessageID = child.id

        let repair = ChatMessageBranchResolver.repairMessageTree(in: session)
        let branch = ChatMessageBranchResolver.activeBranchMessages(in: session)

        XCTAssertTrue(repair.didMutate)
        XCTAssertTrue(repair.didMutateBranch)
        XCTAssertEqual(session.activeRootMessageID, root.id)
        XCTAssertEqual(root.activeChildMessageID, child.id)
        XCTAssertEqual(child.activeChildMessageID, leaf.id)
        XCTAssertNil(leaf.activeChildMessageID)
        XCTAssertEqual(branch.messages.map(\.id), [root.id, child.id, leaf.id])
    }

    func testChatMessageBranchResolverRepairsExternalParentsAndCycles() {
        let session = ChatSession()
        let externalParent = chatMessage(id: uuid(20), content: "external")
        let externalChild = chatMessage(
            id: uuid(21),
            content: "external child",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let cycleA = chatMessage(
            id: uuid(22),
            content: "cycle a",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let cycleB = chatMessage(
            id: uuid(23),
            content: "cycle b",
            createdAt: Date(timeIntervalSince1970: 3)
        )
        externalChild.parentMessage = externalParent
        cycleA.parentMessage = cycleB
        cycleB.parentMessage = cycleA
        session.messages = [cycleB, externalChild, cycleA]

        let repair = ChatMessageBranchResolver.repairMessageTree(in: session)
        let branch = ChatMessageBranchResolver.activeBranchMessages(in: session)

        XCTAssertTrue(repair.didMutate)
        XCTAssertTrue(repair.didMutateBranch)
        XCTAssertNil(externalChild.parentMessage)
        XCTAssertFalse(branch.messages.isEmpty)
        XCTAssertEqual(Set(branch.messages.map(\.id)).count, branch.messages.count)
        XCTAssertNotNil(session.activeRootMessageID)
    }
}
