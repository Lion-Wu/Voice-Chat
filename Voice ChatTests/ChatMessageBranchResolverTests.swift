import XCTest
@testable import Voice_Chat

final class ChatMessageBranchResolverTests: XCTestCase {
    func testChatMessageBranchResolverFallsBackToNewestChildForInvalidActiveChild() {
        let session = ChatSession()
        let root = chatMessage(
            id: uuid(1),
            content: "root",
            createdAt: TestDate.reference
        )
        let olderChild = chatMessage(
            id: uuid(2),
            content: "older child",
            createdAt: TestDate.offset(1)
        )
        let newerChild = chatMessage(
            id: uuid(3),
            content: "newer child",
            createdAt: TestDate.offset(2)
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
            createdAt: TestDate.reference
        )
        let child = chatMessage(
            id: uuid(12),
            content: "child",
            createdAt: TestDate.offset(1)
        )
        let leaf = chatMessage(
            id: uuid(13),
            content: "leaf",
            createdAt: TestDate.offset(2)
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

    func testMessagesThroughTargetUsesOnlyItsAncestorLineage() throws {
        let session = ChatSession()
        let firstUser = chatMessage(
            id: uuid(31),
            content: "first question",
            createdAt: TestDate.reference
        )
        let firstAssistant = chatMessage(
            id: uuid(32),
            content: "first answer",
            isUser: false,
            createdAt: TestDate.offset(1)
        )
        let secondUser = chatMessage(
            id: uuid(33),
            content: "second question",
            createdAt: TestDate.offset(2)
        )
        let secondAssistant = chatMessage(
            id: uuid(34),
            content: "second answer",
            isUser: false,
            createdAt: TestDate.offset(3)
        )
        firstAssistant.parentMessage = firstUser
        secondUser.parentMessage = firstAssistant
        secondAssistant.parentMessage = secondUser
        firstUser.activeChildMessageID = firstAssistant.id
        firstAssistant.activeChildMessageID = secondUser.id
        secondUser.activeChildMessageID = secondAssistant.id
        session.messages = [secondAssistant, firstUser, secondUser, firstAssistant]
        session.activeRootMessageID = firstUser.id
        firstUser.activeChildMessageID = nil

        let activeBranch = ChatMessageBranchResolver.activeBranchMessages(in: session)
        let firstRetryLineage = try XCTUnwrap(
            ChatMessageBranchResolver.messagesThrough(firstUser, in: session)
        )
        let secondRetryLineage = try XCTUnwrap(
            ChatMessageBranchResolver.messagesThrough(secondUser, in: session)
        )

        XCTAssertEqual(
            activeBranch.messages.map(\.id),
            [firstUser.id, firstAssistant.id, secondUser.id, secondAssistant.id]
        )
        XCTAssertEqual(firstRetryLineage.map(\.id), [firstUser.id])
        XCTAssertEqual(
            secondRetryLineage.map(\.id),
            [firstUser.id, firstAssistant.id, secondUser.id]
        )
    }

    func testChatMessageBranchResolverRepairsExternalParentsAndCycles() {
        let session = ChatSession()
        let externalParent = chatMessage(id: uuid(20), content: "external")
        let externalChild = chatMessage(
            id: uuid(21),
            content: "external child",
            createdAt: TestDate.reference
        )
        let cycleA = chatMessage(
            id: uuid(22),
            content: "cycle a",
            createdAt: TestDate.offset(1)
        )
        let cycleB = chatMessage(
            id: uuid(23),
            content: "cycle b",
            createdAt: TestDate.offset(2)
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
