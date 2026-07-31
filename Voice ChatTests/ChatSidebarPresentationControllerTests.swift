import SwiftData
import XCTest
@testable import Voice_Chat

final class ChatSidebarPresentationControllerTests: XCTestCase {
    func testSessionListLoadStateSeparatesLoadingFromRealEmptyContent() {
        XCTAssertEqual(
            SidebarSessionListLoadState.resolve(
                isPersistentStoreAttached: false,
                hasSessions: false,
                hasPublishedGroups: false,
                visibleSearchKeyword: ""
            ),
            .loading
        )
        XCTAssertEqual(
            SidebarSessionListLoadState.resolve(
                isPersistentStoreAttached: true,
                hasSessions: true,
                hasPublishedGroups: false,
                visibleSearchKeyword: ""
            ),
            .loading
        )
        XCTAssertEqual(
            SidebarSessionListLoadState.resolve(
                isPersistentStoreAttached: true,
                hasSessions: false,
                hasPublishedGroups: false,
                visibleSearchKeyword: ""
            ),
            .ready
        )
        XCTAssertEqual(
            SidebarSessionListLoadState.resolve(
                isPersistentStoreAttached: true,
                hasSessions: true,
                hasPublishedGroups: false,
                visibleSearchKeyword: "needle"
            ),
            .ready
        )
    }

    func testSidebarGroupLayoutIgnoresContentOnlyMutation() {
        let first = ChatSession(title: "First")
        let second = ChatSession(title: "Second")
        let current = [
            SidebarSessionGroup(section: .today, sessions: [first, second])
        ]

        first.title = "Updated title"

        XCTAssertTrue(SidebarSessionGrouping.hasSameLayout(
            current,
            as: [
                SidebarSessionGroup(section: .today, sessions: [first, second])
            ]
        ))
        XCTAssertFalse(SidebarSessionGrouping.hasSameLayout(
            current,
            as: [
                SidebarSessionGroup(section: .today, sessions: [second, first])
            ]
        ))
        XCTAssertFalse(SidebarSessionGrouping.hasSameLayout(
            current,
            as: [
                SidebarSessionGroup(section: .yesterday, sessions: [first, second])
            ]
        ))
    }

    func testSessionListPublicationPolicyIgnoresContentOnlyMutation() {
        let first = ChatSession(title: "First")
        let second = ChatSession(title: "Second")
        let current = [first, second]

        first.title = "Updated title"

        XCTAssertFalse(ChatSessionListPublicationPolicy.needsPublication(
            current: current,
            proposed: [first, second]
        ))
        XCTAssertTrue(ChatSessionListPublicationPolicy.needsPublication(
            current: current,
            proposed: [second, first]
        ))
    }

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

    func testNormalSidebarSubtitleUsesPersistedProjection() {
        var controller = ChatSidebarPresentationController()
        let session = makeSession(
            title: "Projection",
            messages: [
                ChatMessage(
                    content: "Relationship content must not drive the normal sidebar row",
                    isUser: false,
                    createdAt: TestDate.reference
                )
            ]
        )
        session.sidebarPreviewText = "Persisted sidebar preview"

        XCTAssertEqual(controller.subtitle(for: session), "Persisted sidebar preview")

        session.messages[0].content = "A later in-memory relationship mutation"
        XCTAssertEqual(controller.subtitle(for: session), "Persisted sidebar preview")
    }

    func testSidebarProjectionPreservesExistingPreviewSemantics() {
        let body = String(repeating: "x", count: 61)
        let message = ChatMessage(
            content: "<think>hidden</think>\n\(body)",
            isUser: false,
            createdAt: TestDate.reference
        )

        XCTAssertEqual(
            ChatSession.sidebarPreviewText(for: message),
            "\(String(body.prefix(60)))…"
        )
    }

    func testSessionMaintainsSidebarProjectionOnlyForLatestMessage() {
        let session = ChatSession(title: "Incremental")
        let latest = ChatMessage(
            content: "Initial latest content",
            isUser: false,
            createdAt: TestDate.offset(1)
        )
        let older = ChatMessage(
            content: "Older content",
            isUser: true,
            createdAt: TestDate.reference
        )

        session.registerMessageActivity(latest)
        XCTAssertEqual(session.lastMessageID, latest.id)
        XCTAssertEqual(session.lastMessageAt, latest.createdAt)
        XCTAssertEqual(session.sidebarPreviewText, "Initial latest content")

        older.content = "Changed older content"
        session.refreshSidebarPreviewIfLatest(older)
        XCTAssertEqual(session.sidebarPreviewText, "Initial latest content")

        latest.content = "Updated latest content"
        session.refreshSidebarPreviewIfLatest(latest)
        XCTAssertEqual(session.sidebarPreviewText, "Updated latest content")
    }

    private func makeSession(title: String, messages: [ChatMessage]) -> ChatSession {
        let session = ChatSession(title: title)
        session.messages = messages
        session.lastMessageAt = messages.max(by: { $0.createdAt < $1.createdAt })?.createdAt
        return session
    }
}

@MainActor
final class StartupDataCoordinatorTests: XCTestCase {
    func testSuccessfulContainerTransitionsFromLoadingToReady() async throws {
        let container = try makeContainer()
        let coordinator = StartupDataCoordinator(containerFactory: { container })

        guard case .loading = coordinator.launchState else {
            return XCTFail("Expected startup to expose the loading shell first")
        }

        guard case .ready(let readyContainer) = await terminalState(of: coordinator) else {
            return XCTFail("Expected startup to enter the ready state")
        }
        XCTAssertTrue(readyContainer === container)
    }

    func testContainerFailureIsShownAsDataFailure() async {
        let error = NSError(
            domain: "StartupDataCoordinatorTests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Unreadable data"]
        )
        let coordinator = StartupDataCoordinator(containerFactory: { throw error })

        guard case .failed(let message) = await terminalState(of: coordinator) else {
            return XCTFail("Expected startup to expose the container failure")
        }
        XCTAssertTrue(message.contains("Unreadable data"))
        XCTAssertTrue(message.contains("[StartupDataCoordinatorTests: 7]"))
    }

    func testPersistentReadFailureTransitionsReadyStateToDataFailure() async throws {
        let container = try makeContainer()
        let coordinator = StartupDataCoordinator(containerFactory: { container })
        let error = NSError(
            domain: "SessionRead",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "Chat headers could not be read"]
        )

        guard case .ready = await terminalState(of: coordinator) else {
            return XCTFail("Expected startup to become ready before reporting a read failure")
        }

        coordinator.reportPersistentStoreReadFailure(error)
        guard case .failed(let message) = coordinator.launchState else {
            return XCTFail("Expected a persistent read failure to replace ready content")
        }
        XCTAssertTrue(message.contains("Chat headers could not be read"))
        XCTAssertTrue(message.contains("[SessionRead: 11]"))
    }

    func testContainerPreparationCompletesBeforeReadyIsPublished() async throws {
        let container = try makeContainer()
        var preparedContainer: ModelContainer?
        let coordinator = StartupDataCoordinator(
            containerFactory: { container },
            prepareContainer: { preparedContainer = $0 }
        )

        guard case .ready(let readyContainer) = await terminalState(of: coordinator) else {
            return XCTFail("Expected startup to enter the ready state")
        }
        XCTAssertTrue(preparedContainer === readyContainer)
    }

    private func terminalState(
        of coordinator: StartupDataCoordinator
    ) async -> StartupDataCoordinator.LaunchState {
        for await state in coordinator.$launchState.values {
            if case .loading = state {
                continue
            }
            return state
        }
        preconditionFailure("Startup state publisher completed before reaching a terminal state")
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ChatSession.self,
            ChatMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
