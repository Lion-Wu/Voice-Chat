//
//  ChatService+StreamingLifecycle.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension ChatService {
    /// Builds the request and starts the URLSession stream on the serial state queue.
    func startStreaming(endpoint: ChatAPIEndpointCandidate, requestBodyData: Data) {
        let request = requestFactory.makeStreamingRequest(
            endpoint: endpoint,
            requestBodyData: requestBodyData,
            apiKey: configurationProvider.apiKey
        )

        activeStreamRequestBodyData = requestBodyData
        streamStartAt = Date()
        isToolContinuationStarting = false
        didEstablishConnection = false
        lastDeltaAt = nil
        beginBackgroundExecutionForCurrentRequest()
        startWatchdog()
        startConnectionWatchdog()

        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }

    func resetStreamState() {
        beginNewStreamCallbackEpoch()
        cancelActiveToolExecution()
        isLegacyThinkStream = false
        sawAnyAssistantToken = false
        sawAnyPrimaryAssistantToken = false
        lmStudioSawAnyReasoningToken = false
        newFormatActive = false
        sentThinkOpen = false
        sentThinkClose = false
        isInsideLegacyThinkTag = false
        shouldTrimNextLegacyThinkLeadingNewline = false
        legacyThinkTagBuffer = ""
        streamFinishedEmitted = false
        lastProcessedSSESequenceNumber = nil
        reasoningDeltaItemIDs.removeAll(keepingCapacity: true)
        outputTextDeltaItemIDs.removeAll(keepingCapacity: true)
        openAIResponsesStreamItemState = .init()
        anthropicStreamState = .init()
        anthropicAssistantContentAccumulator.reset()
        sseParser.reset()
        streamStartAt = nil
        didEstablishConnection = false
        lastDeltaAt = nil
        httpStatusCode = nil
        errorResponseData.removeAll(keepingCapacity: true)
        successResponseData.removeAll(keepingCapacity: true)
        pendingLMStudioStreamErrorMessage = nil
        pendingResponseMetadata = .empty
        activeStreamRequestBodyData = nil
        lastRetryableStreamRequest = nil
        toolCallAccumulator.reset()
        openAIResponsesOutputItems.removeAll(keepingCapacity: true)
        openAIResponsesConversationItems.removeAll(keepingCapacity: true)
        openAIChatCompletionsReasoningDetails.removeAll(keepingCapacity: true)
        openAIChatCompletionsReasoningText = ""
        pendingToolCalls.removeAll(keepingCapacity: true)
        generatingToolActivities.removeAll(keepingCapacity: true)
        isToolContinuationStarting = false
        Task { await toolAuthorizationCoordinator.cancelAll() }
        resetPromptToolGate()
        stopConnectionWatchdog()
        endBackgroundExecutionForCurrentRequest()
    }

    func advanceRequestGeneration() {
        requestGeneration &+= 1
    }

    func cancelActiveToolExecution() {
        activeToolExecutionTask?.cancel()
        activeToolExecutionTask = nil
        activeToolExecutionID = nil
    }

    func beginNewStreamCallbackEpoch() {
        streamCallbackEpoch &+= 1
        streamCallbackAttempt = 1
        invalidatedStreamCallbackAttempts.removeAll(keepingCapacity: true)
    }

    func beginStreamCallbackAttempt(invalidatingCurrentAttempt: Bool) {
        if invalidatingCurrentAttempt, streamCallbackAttempt > 0 {
            invalidatedStreamCallbackAttempts.insert(streamCallbackAttempt)
        }
        streamCallbackAttempt &+= 1
    }

    private func currentStreamCallbackToken() -> ChatStreamCallbackToken {
        ChatStreamCallbackToken(epoch: streamCallbackEpoch, attempt: streamCallbackAttempt)
    }

    private func isValidStreamCallbackToken(_ token: ChatStreamCallbackToken) -> Bool {
        stateQueue.sync {
            token.epoch == streamCallbackEpoch &&
                !invalidatedStreamCallbackAttempts.contains(token.attempt)
        }
    }

    func deliverResponseMetadata(_ metadata: ChatResponseMetadata) {
        let token = currentStreamCallbackToken()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isValidStreamCallbackToken(token) else { return }
            self.onResponseMetadata?(metadata)
        }
    }

    func deliverOpenAIResponsesConversationItems(_ items: [JSONValue]) {
        let token = currentStreamCallbackToken()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isValidStreamCallbackToken(token) else { return }
            self.onOpenAIResponsesConversationItems?(items)
        }
    }

    func deliverError(_ error: Error) {
        let token = currentStreamCallbackToken()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isValidStreamCallbackToken(token) else { return }
            self.onError?(error)
        }
    }

    private func deliverDelta(_ piece: String) {
        let token = currentStreamCallbackToken()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isValidStreamCallbackToken(token) else { return }
            self.onDelta?(piece)
        }
    }

    private func deliverSegment(_ segment: AssistantStreamSegment) {
        let token = currentStreamCallbackToken()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isValidStreamCallbackToken(token) else { return }
            self.onSegment?(segment)
        }
    }

    private func deliverStreamFinished() {
        let token = currentStreamCallbackToken()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isValidStreamCallbackToken(token) else { return }
            self.onStreamFinished?()
        }
    }

    private func deliverToolActivity(_ activity: ChatToolActivity) {
        let token = currentStreamCallbackToken()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isValidStreamCallbackToken(token) else { return }
            self.onToolActivity?(activity)
        }
    }

    func isCurrentRequestGeneration(_ generation: UInt64) -> Bool {
        !isCancelled && activeToolLoopContext?.requestGeneration == generation
    }

    func isCurrentRequestGenerationAsync(_ generation: UInt64) async -> Bool {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                continuation.resume(returning: self?.isCurrentRequestGeneration(generation) == true)
            }
        }
    }

    func clearActiveEndpointCandidate() {
        activeEndpointCandidate = nil
    }

    func mergeResponseMetadata(_ update: ChatResponseMetadata) {
        pendingResponseMetadata.merge(update)
        let snapshot = pendingResponseMetadata
        deliverResponseMetadata(snapshot)
    }

    func failCurrentStreamWithServerError(
        _ message: String,
        statusCode: Int? = nil,
        includeHTTPStatus: Bool = true
    ) {
        let resolvedStatusCode = includeHTTPStatus ? (statusCode ?? httpStatusCode) : statusCode
        failCurrentStream(with: ChatNetworkError.serverError(
            statusCode: resolvedStatusCode,
            message: message
        ))
    }

    func failCurrentStream(with error: Error) {
        isCancelled = true
        advanceRequestGeneration()
        activeStreamRequestBodyData = nil
        dataTask?.cancel()
        dataTask = nil
        cancelActiveToolExecution()
        stopConnectionWatchdog()
        stopWatchdog()
        activeToolLoopContext = nil
        Task { await toolAuthorizationCoordinator.cancelAll() }
        clearActiveEndpointCandidate()
        endBackgroundExecutionForCurrentRequest()
        deliverError(error)
    }

    func emitDelta(_ piece: String, marksPrimaryOutput: Bool = true) {
        guard !isCancelled else { return }
        lastDeltaAt = Date()
        deliverDelta(piece)
        sawAnyAssistantToken = true
        if marksPrimaryOutput {
            sawAnyPrimaryAssistantToken = true
        }
    }

    func emitSegment(_ segment: AssistantStreamSegment, marksPrimaryOutput: Bool) {
        guard !isCancelled else { return }
        lastDeltaAt = Date()
        deliverSegment(segment)
        sawAnyAssistantToken = true
        if marksPrimaryOutput {
            sawAnyPrimaryAssistantToken = true
        }
    }

    func emitStreamFinishedOnce() {
        guard !isCancelled else { return }
        finishStreamOrRunPendingTools()
    }

    func finishStreamOrRunPendingTools() {
        guard !isCancelled, !isToolContinuationStarting else { return }
        recordCurrentOpenAIResponsesOutputItemsIfNeeded()
        if shouldRunToolLoopInsteadOfFinishing() {
            runPendingToolCallsAndContinue()
            return
        }
        guard !isCancelled else { return }
        guard !streamFinishedEmitted else { return }
        streamFinishedEmitted = true
        activeToolLoopContext = nil
        advanceRequestGeneration()
        activeStreamRequestBodyData = nil
        lastRetryableStreamRequest = nil
        clearActiveEndpointCandidate()
        deliverStreamFinished()
    }

    func emitToolActivity(_ activity: ChatToolActivity) {
        deliverToolActivity(activity)
    }

    func emitToolActivity(_ activity: ChatToolActivity, requestGeneration: UInt64) {
        stateQueue.async { [weak self] in
            guard let self,
                  self.isCurrentRequestGeneration(requestGeneration) else {
                return
            }
            self.deliverToolActivity(activity)
        }
    }
}
