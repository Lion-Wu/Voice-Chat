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
        let session = ChatSession(title: "Example Conversation")
        let assistant = ChatMessage(content: "hello", isUser: false)
        session.messages.append(assistant)
        runtime.currentAssistantMessageID = assistant.id
        runtime.streamingAssistantMessageID = assistant.id
        runtime.streamingAssistantFingerprint = ContentFingerprint.make(assistant.content)

        let finalized = runtime.finalizeActiveAssistantMessage(
            in: session,
            reason: "completed",
            finishedAt: TestDate.reference,
            errorDescription: nil
        )

        XCTAssertEqual(finalized?.id, assistant.id)
        XCTAssertNil(runtime.streamingAssistantMessageID)
        XCTAssertNil(runtime.streamingAssistantFingerprint)
        XCTAssertFalse(assistant.isActive)
    }

    func testCompleteAfterErrorFinalizesInterruptedAssistantAndBuildsErrorMessage() {
        let runtime = makeRuntime()
        let session = ChatSession(title: "Example Conversation")
        let assistant = ChatMessage(content: "partial", isUser: false)
        session.messages.append(assistant)
        runtime.markActive(pendingParentMessageID: uuid(53))
        runtime.currentAssistantMessageID = assistant.id

        let completion = runtime.completeAfterError(
            LocalizedRuntimeError(message: "network down"),
            in: session,
            now: TestDate.reference
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
        let session = ChatSession(title: "Example Conversation")
        let assistant = ChatMessage(content: "done", isUser: false)
        session.messages.append(assistant)
        runtime.markActive(pendingParentMessageID: uuid(54))
        runtime.currentAssistantMessageID = assistant.id

        let completed = runtime.completeSuccessfully(
            in: session,
            finishedAt: TestDate.reference
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
        let session = ChatSession(title: "Example Conversation")
        let assistant = ChatMessage(content: "partial", isUser: false)
        session.messages.append(assistant)
        runtime.markActive(pendingParentMessageID: uuid(55))
        runtime.currentAssistantMessageID = assistant.id

        let completion = runtime.cancelCurrentRequest(
            in: session,
            finishedAt: TestDate.reference
        )

        XCTAssertNil(completion.assistantMessageIDForBranchRestore)
        XCTAssertFalse(runtime.hasActiveTextRequest)
        XCTAssertNil(runtime.currentAssistantMessageID)
        XCTAssertNil(runtime.pendingAssistantParentMessageID)
        XCTAssertFalse(assistant.isActive)
        XCTAssertEqual(assistant.finishReason, "stopped")
    }

    func testPrepareForBranchRestartFinalizesAssistantAndClearsTracking() {
        let runtime = makeRuntime()
        let session = ChatSession(title: "Example Conversation")
        let assistant = ChatMessage(content: "old", isUser: false)
        session.messages.append(assistant)
        runtime.currentAssistantMessageID = assistant.id

        runtime.prepareForBranchRestart(
            in: session,
            reason: "retry",
            finishedAt: TestDate.reference
        )

        XCTAssertFalse(runtime.hasActiveTextRequest)
        XCTAssertNil(runtime.currentAssistantMessageID)
        XCTAssertNil(runtime.pendingAssistantParentMessageID)
        XCTAssertFalse(assistant.isActive)
        XCTAssertEqual(assistant.finishReason, "retry")
    }

    func testNewRequestRetryScopeStartsAtFirstRetryAfterEarlierRequestRecovered() {
        let runtime = makeRuntime()
        var states: [ChatStreamRetryStatusController.PublishedState] = []
        runtime.bindRetryState { states.append($0) }

        _ = runtime.planRetry(
            after: URLError(.timedOut),
            errorText: "first request failed",
            hasAssistantMessage: false
        )
        runtime.clearRetryStateAfterProgressIfNeeded()
        _ = runtime.planRetry(
            after: URLError(.timedOut),
            errorText: "first request failed again",
            hasAssistantMessage: true
        )

        runtime.beginRequestRetryScope()

        XCTAssertEqual(
            states.last,
            .init(isRetrying: false, retryAttempt: 0, retryLastError: nil)
        )

        let continuationRetry = runtime.planRetry(
            after: URLError(.timedOut),
            errorText: "continuation failed",
            hasAssistantMessage: true
        )
        XCTAssertEqual(continuationRetry.state.retryAttempt, 1)
        XCTAssertEqual(continuationRetry.state.retryLastError, "continuation failed")
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
    var onSegment: (@MainActor (AssistantStreamSegment) -> Void)?
    var onOpenAIResponsesConversationItems: (@MainActor ([JSONValue]) -> Void)?
    var onError: (@MainActor (Error) -> Void)?
    var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)?
    var onToolActivity: (@MainActor (ChatToolActivity) -> Void)?
    var onStreamFinished: (@MainActor () -> Void)?

    func fetchStreamedData(
        messages: [ChatMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) {}

    func retryLastFailedStreamRequest() -> Bool { false }

    func cancelStreaming() {}

    func resolveToolAuthorization(requestID: String, allowed: Bool) {}
}

private struct LocalizedRuntimeError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
