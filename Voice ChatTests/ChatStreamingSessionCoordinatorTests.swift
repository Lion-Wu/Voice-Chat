import XCTest
@testable import Voice_Chat

@MainActor
final class ChatStreamingSessionCoordinatorTests: XCTestCase {
    func testUpdateConfigurationDefersDuringActiveRequestThenAppliesWhenIdle() {
        let initial = chatConfig(model: "initial")
        let next = chatConfig(model: "next")
        var createdModels: [String] = []
        let initialService = StubChatStreamingService()
        let coordinator = ChatStreamingSessionCoordinator(
            configuration: initial,
            service: initialService,
            serviceFactory: { configuration in
                createdModels.append(configuration.modelIdentifier)
                return StubChatStreamingService()
            }
        )

        XCTAssertEqual(
            coordinator.updateConfiguration(next, isActiveTextRequest: true),
            .deferred
        )
        XCTAssertEqual(coordinator.configuration, initial)
        XCTAssertTrue(createdModels.isEmpty)

        XCTAssertEqual(
            coordinator.applyDeferredConfigurationIfIdle(isActiveTextRequest: false),
            .applied
        )
        XCTAssertEqual(coordinator.configuration, next)
        XCTAssertEqual(createdModels, ["next"])
    }

    func testCallbacksAreReboundWhenConfigurationApplies() {
        let initial = chatConfig(model: "initial")
        let next = chatConfig(model: "next")
        let initialService = StubChatStreamingService()
        let replacementService = StubChatStreamingService()
        let coordinator = ChatStreamingSessionCoordinator(
            configuration: initial,
            service: initialService,
            serviceFactory: { _ in replacementService }
        )
        var receivedDeltas: [String] = []
        coordinator.bindHandlers(
            onDelta: { receivedDeltas.append($0) },
            onSegment: { _ in },
            onOpenAIResponsesConversationItems: { _ in },
            onError: { _ in },
            onResponseMetadata: { _ in },
            onToolActivity: { _ in },
            onStreamFinished: {}
        )

        let staleCallback = initialService.onDelta
        initialService.onDelta?("old")
        XCTAssertEqual(
            coordinator.updateConfiguration(next, isActiveTextRequest: false),
            .applied
        )
        staleCallback?("stale")
        replacementService.onDelta?("new")

        XCTAssertEqual(receivedDeltas, ["old", "new"])
    }

    func testChatServiceDropsQueuedCallbacksFromInvalidatedRetryAttempt() async {
        let service = ChatService(configurationProvider: chatConfig(model: "model"))
        let delivered = expectation(description: "current callback delivered")
        var receivedDeltas: [String] = []
        service.onDelta = { delta in
            receivedDeltas.append(delta)
            delivered.fulfill()
        }

        await withCheckedContinuation { continuation in
            service.stateQueue.async {
                service.beginNewStreamCallbackEpoch()
                service.emitDelta("stale")
                service.beginStreamCallbackAttempt(invalidatingCurrentAttempt: true)
                service.emitDelta("current")
                continuation.resume()
            }
        }
        await fulfillment(of: [delivered], timeout: 1.0)

        XCTAssertEqual(receivedDeltas, ["current"])
    }

    func testChatServiceFinalErrorPreservesCallbacksAlreadyProducedByAttempt() async {
        let service = ChatService(configurationProvider: chatConfig(model: "model"))
        let errorDelivered = expectation(description: "error callback delivered")
        var receivedDeltas: [String] = []
        var receivedErrorCount = 0
        service.onDelta = { receivedDeltas.append($0) }
        service.onError = { _ in
            receivedErrorCount += 1
            errorDelivered.fulfill()
        }

        await withCheckedContinuation { continuation in
            service.stateQueue.async {
                service.beginNewStreamCallbackEpoch()
                service.emitDelta("partial")
                service.deliverError(ChatNetworkError.emptyResponse)
                continuation.resume()
            }
        }
        await fulfillment(of: [errorDelivered], timeout: 1.0)

        XCTAssertEqual(receivedDeltas, ["partial"])
        XCTAssertEqual(receivedErrorCount, 1)
    }

    func testChatServiceSuccessfulStageTransitionPreservesQueuedConversationSnapshot() async {
        let service = ChatService(configurationProvider: chatConfig(model: "model"))
        let delivered = expectation(description: "completed stage snapshot delivered")
        let snapshot: [JSONValue] = [
            .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-1"),
                "output": .string("success")
            ])
        ]
        var receivedSnapshots: [[JSONValue]] = []
        service.onOpenAIResponsesConversationItems = { items in
            receivedSnapshots.append(items)
            delivered.fulfill()
        }

        await withCheckedContinuation { continuation in
            service.stateQueue.async {
                service.beginNewStreamCallbackEpoch()
                service.deliverOpenAIResponsesConversationItems(snapshot)
                service.beginStreamCallbackAttempt(invalidatingCurrentAttempt: false)
                continuation.resume()
            }
        }
        await fulfillment(of: [delivered], timeout: 1.0)

        XCTAssertEqual(receivedSnapshots, [snapshot])
    }

    func testChatServiceIncompleteResponseCarriesTerminalSnapshotAfterInvalidation() async {
        let service = ChatService(configurationProvider: chatConfig(model: "model"))
        let errorDelivered = expectation(description: "incomplete response delivered")
        var receivedSegments: [AssistantStreamSegment] = []
        var receivedError: ChatIncompleteResponseError?
        service.onSegment = { receivedSegments.append($0) }
        service.onError = { error in
            receivedError = error as? ChatIncompleteResponseError
            errorDelivered.fulfill()
        }
        let terminalSegments: [AssistantStreamSegment] = [
            .reasoning(id: "r1", text: "Need more room."),
            .text(id: "m1", text: "Partial answer")
        ]
        let metadata = ChatResponseMetadata(
            providerResponseID: "resp_incomplete",
            outputTokenCount: 12,
            finishReason: "incomplete"
        )

        await withCheckedContinuation { continuation in
            service.stateQueue.async {
                service.beginNewStreamCallbackEpoch()
                service.isCancelled = false
                service.emitSegment(.text(id: "stale", text: "stale"), marksPrimaryOutput: true)
                service.pendingResponseMetadata = metadata
                service.applyOpenAICompatibleStreamActions([
                    .incomplete(message: "Response was incomplete.", segments: terminalSegments)
                ])
                continuation.resume()
            }
        }
        await fulfillment(of: [errorDelivered], timeout: 1.0)

        XCTAssertEqual(receivedSegments, [.text(id: "stale", text: "stale")])
        XCTAssertEqual(receivedError?.segments, terminalSegments)
        XCTAssertEqual(receivedError?.metadata, metadata)
    }

    func testChatServiceDeliversFailureMetadataBeforeFinalError() async {
        let service = ChatService(configurationProvider: chatConfig(model: "model"))
        let errorDelivered = expectation(description: "error delivered")
        var events: [String] = []
        service.onResponseMetadata = { metadata in
            events.append("metadata:\(metadata.providerResponseID ?? "")")
        }
        service.onError = { _ in
            events.append("error")
            errorDelivered.fulfill()
        }

        await withCheckedContinuation { continuation in
            service.stateQueue.async {
                service.beginNewStreamCallbackEpoch()
                service.isCancelled = false
                service.applyOpenAICompatibleStreamActions([
                    .metadata(ChatResponseMetadata(providerResponseID: "resp_failed")),
                    .fail("failed")
                ])
                continuation.resume()
            }
        }
        await fulfillment(of: [errorDelivered], timeout: 1.0)

        XCTAssertEqual(events, ["metadata:resp_failed", "error"])
    }

    func testChatServiceRetryAssignsNewGenerationToRestoredToolContext() async throws {
        let service = ChatService(configurationProvider: chatConfig(model: "model"))
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/models"))
        )
        var context = ChatToolLoopContext(
            currentPayload: ChatToolLoopPayload(messages: []),
            developerPrompt: nil,
            includeImagesInUserContent: false,
            model: "model",
            endpoint: endpoint,
            iteration: 1,
            previousResponseID: nil
        )
        context.requestGeneration = 7
        let retryContext = context

        await withCheckedContinuation { continuation in
            service.stateQueue.async {
                service.requestGeneration = 7
                service.isCancelled = true
                service.lastRetryableStreamRequest = ChatRetryableStreamRequest(
                    endpoint: endpoint,
                    body: Data("{}".utf8),
                    toolLoopContext: retryContext
                )
                continuation.resume()
            }
        }

        XCTAssertTrue(service.retryLastFailedStreamRequest())
        let state = await withCheckedContinuation { continuation in
            service.stateQueue.async {
                continuation.resume(returning: (
                    service.requestGeneration,
                    service.activeToolLoopContext?.requestGeneration,
                    service.isCurrentRequestGeneration(7)
                ))
            }
        }

        XCTAssertEqual(state.0, 8)
        XCTAssertEqual(state.1, 8)
        XCTAssertFalse(state.2)
        service.cancelStreaming()
    }

    func testChatServiceDoesNotFinishWhileToolContinuationIsStarting() async {
        let service = ChatService(configurationProvider: chatConfig(model: "model"))
        let unexpectedFinish = expectation(description: "stream must remain active")
        unexpectedFinish.isInverted = true
        service.onStreamFinished = { unexpectedFinish.fulfill() }

        let emittedFinish = await withCheckedContinuation { continuation in
            service.stateQueue.async {
                service.beginNewStreamCallbackEpoch()
                service.isToolContinuationStarting = true
                service.finishStreamOrRunPendingTools()
                continuation.resume(returning: service.streamFinishedEmitted)
            }
        }

        XCTAssertFalse(emittedFinish)
        await fulfillment(of: [unexpectedFinish], timeout: 0.1)
    }

    func testProtocolFinishIsNotOverwrittenByLaterTransportError() async throws {
        let service = ChatService(configurationProvider: chatConfig(model: "model"))
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/models"))
        )
        let task = URLSession(configuration: .ephemeral).dataTask(
            with: try XCTUnwrap(URL(string: "https://example.invalid/v1/chat/completions"))
        )
        let finished = expectation(description: "protocol finish remains authoritative")
        let unexpectedError = expectation(description: "late transport error is ignored")
        unexpectedError.isInverted = true
        service.onStreamFinished = { finished.fulfill() }
        service.onError = { _ in unexpectedError.fulfill() }

        await withCheckedContinuation { continuation in
            service.stateQueue.async {
                service.beginNewStreamCallbackEpoch()
                service.isCancelled = false
                service.activeEndpointCandidate = endpoint
                service.activeStreamRequestBodyData = Data("{}".utf8)
                service.dataTask = task
                service.emitDelta("ok")
                service.finishStreamOrRunPendingTools()
                service.urlSession(
                    URLSession.shared,
                    task: task,
                    didCompleteWithError: URLError(.networkConnectionLost)
                )
                continuation.resume()
            }
        }

        await fulfillment(of: [finished, unexpectedError], timeout: 0.2)
        let finalState = await withCheckedContinuation { continuation in
            service.stateQueue.async {
                continuation.resume(returning: (service.streamFinishedEmitted, service.dataTask == nil))
            }
        }
        XCTAssertTrue(finalState.0)
        XCTAssertTrue(finalState.1)
    }

    func testToolContinuationProcessingActivitySurvivesAttemptReset() async throws {
        var toolSettings = ToolUseSettings.defaults
        toolSettings.isEnabled = true
        toolSettings.deviceContextEnabled = true
        let service = ChatService(
            configurationProvider: ChatServiceConfiguration(
                apiBaseURL: "https://example.invalid/v1",
                modelIdentifier: "model",
                apiKey: "key",
                toolUseSettings: toolSettings
            ),
            toolExecutor: ImmediateChatToolExecutor()
        )
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/models"))
        )
        var mutableContext = ChatToolLoopContext(
            currentPayload: ChatToolLoopPayload(messages: []),
            developerPrompt: nil,
            includeImagesInUserContent: false,
            model: "model",
            endpoint: endpoint,
            iteration: 0,
            previousResponseID: nil
        )
        mutableContext.requestGeneration = 1
        let context = mutableContext
        let call = ChatToolCallEnvelope(
            callID: "call-device",
            name: ChatToolID.deviceContext.rawValue,
            argumentsJSON: "{}",
            provider: .openAI
        )
        let processing = expectation(description: "processing activity uses continuation attempt")
        service.onToolActivity = { activity in
            if activity.phase == .processing {
                processing.fulfill()
            }
        }

        await withCheckedContinuation { continuation in
            service.stateQueue.async {
                service.beginNewStreamCallbackEpoch()
                service.requestGeneration = 1
                service.isCancelled = false
                service.activeEndpointCandidate = endpoint
                service.activeToolLoopContext = context
                service.pendingToolCalls = [call]
                service.runPendingToolCallsAndContinue()
                continuation.resume()
            }
        }

        await fulfillment(of: [processing], timeout: 1.0)
        service.cancelStreaming()
    }

    func testBackgroundInterruptionCancelsToolExecutionWithoutRetryingStaleRequest() async throws {
        let executor = SuspendedChatToolExecutor()
        var toolSettings = ToolUseSettings.defaults
        toolSettings.isEnabled = true
        toolSettings.timeEnabled = true
        let service = ChatService(
            configurationProvider: ChatServiceConfiguration(
                apiBaseURL: "https://example.invalid/v1",
                modelIdentifier: "model",
                apiKey: "key",
                toolUseSettings: toolSettings
            ),
            toolExecutor: executor
        )
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/models"))
        )
        var mutableContext = ChatToolLoopContext(
            currentPayload: ChatToolLoopPayload(messages: []),
            developerPrompt: nil,
            includeImagesInUserContent: false,
            model: "model",
            endpoint: endpoint,
            iteration: 0,
            previousResponseID: nil
        )
        mutableContext.requestGeneration = 1
        let context = mutableContext
        let call = ChatToolCallEnvelope(
            callID: "call-time",
            name: ChatToolID.systemGetTime.rawValue,
            argumentsJSON: "{}",
            provider: .openAI
        )

        await withCheckedContinuation { continuation in
            service.stateQueue.async {
                service.beginNewStreamCallbackEpoch()
                service.requestGeneration = 1
                service.isCancelled = false
                service.activeEndpointCandidate = endpoint
                service.activeToolLoopContext = context
                service.activeStreamRequestBodyData = Data("stale-model-request".utf8)
                service.pendingToolCalls = [call]
                service.runPendingToolCallsAndContinue()
                continuation.resume()
            }
        }

        for _ in 0..<100 {
            if await executor.snapshot().started { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let startedState = await executor.snapshot()
        XCTAssertTrue(startedState.started)

        let interruptionState = await withCheckedContinuation { continuation in
            service.stateQueue.async {
                let requestBodyWasCleared = service.activeStreamRequestBodyData == nil
                let interrupted = service.cancelCurrentStreamForBackgroundInterruption()
                continuation.resume(returning: (
                    requestBodyWasCleared,
                    interrupted,
                    service.lastRetryableStreamRequest == nil
                ))
            }
        }

        for _ in 0..<100 {
            if await executor.snapshot().cancellationObserved { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let executorState = await executor.snapshot()

        XCTAssertTrue(interruptionState.0)
        XCTAssertTrue(interruptionState.1)
        XCTAssertTrue(interruptionState.2)
        XCTAssertTrue(executorState.cancellationObserved)
        XCTAssertFalse(executorState.performedSideEffect)
    }

    private func chatConfig(model: String) -> ChatServiceConfiguration {
        ChatServiceConfiguration(
            apiBaseURL: "http://localhost:1234",
            modelIdentifier: model,
            apiKey: "key"
        )
    }
}

private struct ImmediateChatToolExecutor: ChatToolExecuting {
    func execute(
        _ call: ChatToolCallEnvelope,
        settings: ToolUseSettings,
        endpoint: ChatAPIEndpointCandidate
    ) async -> ChatToolResultEnvelope {
        ChatToolResultEnvelope(
            callID: call.callID,
            name: call.name,
            status: .success,
            payload: ["ok": .bool(true)],
            summary: "completed"
        )
    }
}

private actor SuspendedChatToolExecutor: ChatToolExecuting {
    struct Snapshot: Sendable {
        let started: Bool
        let cancellationObserved: Bool
        let performedSideEffect: Bool
    }

    private var started = false
    private var cancellationObserved = false
    private var performedSideEffect = false

    func execute(
        _ call: ChatToolCallEnvelope,
        settings: ToolUseSettings,
        endpoint: ChatAPIEndpointCandidate
    ) async -> ChatToolResultEnvelope {
        started = true
        do {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            performedSideEffect = true
            return ChatToolResultEnvelope(
                callID: call.callID,
                name: call.name,
                status: .success,
                payload: [:],
                summary: "completed"
            )
        } catch is CancellationError {
            cancellationObserved = true
            return ChatToolResultEnvelope(
                callID: call.callID,
                name: call.name,
                status: .failed,
                payload: [:],
                summary: "cancelled"
            )
        } catch {
            return ChatToolResultEnvelope(
                callID: call.callID,
                name: call.name,
                status: .failed,
                payload: [:],
                summary: error.localizedDescription
            )
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            started: started,
            cancellationObserved: cancellationObserved,
            performedSideEffect: performedSideEffect
        )
    }
}

@MainActor
private final class StubChatStreamingService: ChatStreamingService {
    var onDelta: (@MainActor (String) -> Void)?
    var onSegment: (@MainActor (AssistantStreamSegment) -> Void)?
    var onOpenAIResponsesConversationItems: (@MainActor ([JSONValue]) -> Void)?
    var onError: (@MainActor (Error) -> Void)?
    var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)?
    var onToolActivity: (@MainActor (ChatToolActivity) -> Void)?
    var onStreamFinished: (@MainActor () -> Void)?

    private(set) var didCancel = false
    private(set) var requestedMessages: [ChatMessage] = []

    func fetchStreamedData(
        messages: [ChatMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) {
        requestedMessages = messages
    }

    func retryLastFailedStreamRequest() -> Bool {
        false
    }

    func cancelStreaming() {
        didCancel = true
    }

    func resolveToolAuthorization(requestID: String, allowed: Bool) {}
}
