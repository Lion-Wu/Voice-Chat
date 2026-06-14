import XCTest
@testable import Voice_Chat

@MainActor
final class ChatTextRequestRuntimeTests: XCTestCase {
    func testRuntimePublishesActivityStateAndTracksAssistantIDs() {
        let runtime = makeRuntime()
        var states: [ChatRequestActivityController.PublishedState] = []

        runtime.bindActivityState { states.append($0) }
        runtime.markActive(pendingParentMessageID: uuid(51))
        runtime.currentAssistantMessageID = uuid(52)
        runtime.markAssistantDeltaStarted()
        runtime.markInactive()

        XCTAssertEqual(states, [
            .init(isLoading: false, isPriming: false),
            .init(isLoading: true, isPriming: true),
            .init(isLoading: true, isPriming: false),
            .init(isLoading: false, isPriming: false)
        ])
        XCTAssertEqual(runtime.pendingAssistantParentMessageID, uuid(51))
        XCTAssertEqual(runtime.currentAssistantMessageID, uuid(52))
    }

    func testRuntimeDefersConfigurationUpdatesWhileActive() {
        let initial = chatConfig(model: "initial")
        let next = chatConfig(model: "next")
        let runtime = makeRuntime(configuration: initial)

        runtime.markActive(pendingParentMessageID: nil)

        XCTAssertEqual(runtime.updateConfiguration(next), .deferred)
        XCTAssertEqual(runtime.configuration, initial)

        runtime.markInactive()

        XCTAssertEqual(runtime.applyDeferredConfigurationIfIdle(), .applied)
        XCTAssertEqual(runtime.configuration, next)
    }

    func testRuntimeClearsStreamingAnchorWhenFinalizedMessageMatches() {
        let runtime = makeRuntime()
        let session = ChatSession(title: "Test")
        let assistant = ChatMessage(content: "hello", isUser: false)
        session.messages.append(assistant)
        runtime.currentAssistantMessageID = assistant.id
        runtime.streamingAssistantMessageID = assistant.id
        runtime.streamingAssistantFingerprint = ContentFingerprint.make(assistant.content)

        let finalized = runtime.finalizeActiveAssistantMessage(
            in: session,
            reason: "completed",
            finishedAt: Date(),
            errorDescription: nil
        )

        XCTAssertEqual(finalized?.id, assistant.id)
        XCTAssertNil(runtime.streamingAssistantMessageID)
        XCTAssertNil(runtime.streamingAssistantFingerprint)
        XCTAssertFalse(assistant.isActive)
    }

    func testCompleteAfterErrorFinalizesInterruptedAssistantAndBuildsErrorMessage() {
        let runtime = makeRuntime()
        let session = ChatSession(title: "Test")
        let assistant = ChatMessage(content: "partial", isUser: false)
        session.messages.append(assistant)
        runtime.markActive(pendingParentMessageID: uuid(53))
        runtime.currentAssistantMessageID = assistant.id

        let completion = runtime.completeAfterError(
            LocalizedRuntimeError(message: "network down"),
            in: session,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(completion.errorText, "network down")
        XCTAssertEqual(completion.interruptedMessage?.id, assistant.id)
        XCTAssertEqual(completion.pendingParentMessageID, uuid(53))
        XCTAssertEqual(completion.errorMessage.content, "!error:network down")
        XCTAssertEqual(runtime.interruptedAssistantMessageID, assistant.id)
        XCTAssertNil(runtime.currentAssistantMessageID)
        XCTAssertNil(runtime.pendingAssistantParentMessageID)
        XCTAssertFalse(runtime.hasActiveTextRequest)
        XCTAssertFalse(assistant.isActive)
        XCTAssertEqual(assistant.finishReason, "error")
    }

    func testCompleteSuccessfullyClearsActivityAndAssistantTracking() {
        let runtime = makeRuntime()
        let session = ChatSession(title: "Test")
        let assistant = ChatMessage(content: "done", isUser: false)
        session.messages.append(assistant)
        runtime.markActive(pendingParentMessageID: uuid(54))
        runtime.currentAssistantMessageID = assistant.id

        let completed = runtime.completeSuccessfully(
            in: session,
            finishedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(completed?.id, assistant.id)
        XCTAssertFalse(runtime.hasActiveTextRequest)
        XCTAssertNil(runtime.currentAssistantMessageID)
        XCTAssertNil(runtime.pendingAssistantParentMessageID)
        XCTAssertFalse(assistant.isActive)
        XCTAssertEqual(assistant.finishReason, "completed")
    }

    func testCancelCurrentRequestReturnsAssistantIDForBranchRestoreAndClearsRuntimeState() {
        let runtime = makeRuntime()
        let session = ChatSession(title: "Test")
        let assistant = ChatMessage(content: "partial", isUser: false)
        session.messages.append(assistant)
        runtime.markActive(pendingParentMessageID: uuid(55))
        runtime.currentAssistantMessageID = assistant.id

        let completion = runtime.cancelCurrentRequest(
            in: session,
            finishedAt: Date(timeIntervalSince1970: 300)
        )

        XCTAssertEqual(completion.assistantMessageIDForBranchRestore, assistant.id)
        XCTAssertFalse(runtime.hasActiveTextRequest)
        XCTAssertNil(runtime.currentAssistantMessageID)
        XCTAssertNil(runtime.pendingAssistantParentMessageID)
        XCTAssertFalse(assistant.isActive)
        XCTAssertEqual(assistant.finishReason, "cancelled")
    }

    func testPrepareForBranchRestartFinalizesAssistantAndClearsTracking() {
        let runtime = makeRuntime()
        let session = ChatSession(title: "Test")
        let assistant = ChatMessage(content: "old", isUser: false)
        session.messages.append(assistant)
        runtime.currentAssistantMessageID = assistant.id

        runtime.prepareForBranchRestart(
            in: session,
            reason: "retry",
            finishedAt: Date(timeIntervalSince1970: 400)
        )

        XCTAssertFalse(runtime.hasActiveTextRequest)
        XCTAssertNil(runtime.currentAssistantMessageID)
        XCTAssertNil(runtime.pendingAssistantParentMessageID)
        XCTAssertFalse(assistant.isActive)
        XCTAssertEqual(assistant.finishReason, "retry")
    }

    private func makeRuntime(configuration: ChatServiceConfiguration? = nil) -> ChatTextRequestRuntime {
        ChatTextRequestRuntime(
            configuration: configuration ?? chatConfig(model: "runtime"),
            service: StubRuntimeChatService(),
            serviceFactory: { _ in StubRuntimeChatService() }
        )
    }

    private func chatConfig(model: String) -> ChatServiceConfiguration {
        ChatServiceConfiguration(
            apiBaseURL: "http://localhost:1234",
            modelIdentifier: model,
            apiKey: "key"
        )
    }
}

@MainActor
private final class StubRuntimeChatService: ChatStreamingService {
    var onDelta: (@MainActor (String) -> Void)?
    var onError: (@MainActor (Error) -> Void)?
    var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)?
    var onStreamFinished: (@MainActor () -> Void)?

    func fetchStreamedData(
        messages: [ChatMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) {}

    func cancelStreaming() {}
}

private struct LocalizedRuntimeError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
