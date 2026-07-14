//
//  ChatService+URLSessionDelegate.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension ChatService {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let currentTask = self.dataTask, dataTask === currentTask else {
            completionHandler(.cancel)
            return
        }
        markConnectionEstablishedIfNeeded()
        if let http = response as? HTTPURLResponse {
            httpStatusCode = http.statusCode
            if !(200...299).contains(http.statusCode) {
                errorResponseData.removeAll(keepingCapacity: true)
            }
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData _: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend _: Int64
    ) {
        guard let currentTask = self.dataTask, task === currentTask else { return }
        guard totalBytesSent > 0 else { return }
        markConnectionEstablishedIfNeeded()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let currentTask = self.dataTask, dataTask === currentTask else { return }
        guard !isCancelled else { return }
        markConnectionEstablishedIfNeeded()

        if let status = httpStatusCode, !(200...299).contains(status) {
            if errorResponseData.count < errorBodyCaptureLimit {
                let remaining = errorBodyCaptureLimit - errorResponseData.count
                errorResponseData.append(data.prefix(remaining))
            }
            return
        }

        if successResponseData.count < successBodyCaptureLimit {
            let remaining = successBodyCaptureLimit - successResponseData.count
            successResponseData.append(data.prefix(remaining))
        }

        let parserResult = sseParser.append(data)
        guard case let .frames(frames) = parserResult else {
            isCancelled = true
            dataTask.cancel()
            stopWatchdog()
            deliverError(ChatNetworkError.serverError(
                statusCode: nil,
                message: NSLocalizedString("Stream payload exceeded safety limit", comment: "Shown when streamed SSE data exceeds the configured memory safety cap")
            ))
            return
        }

        for frame in frames {
            guard !isCancelled else { return }
            if frame.isDone {
                guard !isToolContinuationStarting else { return }
                sseParser.clearPendingEventType()
                flushOpenAIChatCompletionsPendingOutput()
                if shouldGatePromptTools() {
                    handlePromptToolFinish()
                    return
                }
                if shouldRunToolLoopInsteadOfFinishing() {
                    runPendingToolCallsAndContinue()
                    return
                }
                guard !isCancelled else { return }
                if newFormatActive && sentThinkOpen && !sentThinkClose && !isLegacyThinkStream {
                    emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                    sentThinkClose = true
                }
                if sawAnyPrimaryAssistantToken {
                    emitStreamFinishedOnce()
                    stopWatchdog()
                }
                return
            }

            guard let jsonData = frame.jsonData else { continue }
            let activeStyle = activeEndpointCandidate?.style ?? .openAIResponses

            switch activeStyle {
            case .openAIResponses, .openAIChatCompletions:
                if handleOpenAICompatibleStreamPayload(jsonData, fallbackType: frame.eventType) {
                    sseParser.clearPendingEventType()
                }

            case .anthropicMessages:
                if let anthropicEvent = try? decoder.decode(AnthropicStreamEvent.self, from: jsonData),
                   anthropicEvent.type != nil {
                    sseParser.clearPendingEventType()
                    handleAnthropicStreamEvent(anthropicEvent)
                }

            case .lmStudioRESTV1:
                if let lmStudioEvent = try? decoder.decode(LMStudioChatStreamEvent.self, from: jsonData) {
                    handleLMStudioStreamEvent(lmStudioEvent, fallbackType: frame.eventType)
                    sseParser.clearPendingEventType()
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let currentTask = self.dataTask, task === currentTask else { return }
        if streamFinishedEmitted {
            stopConnectionWatchdog()
            stopWatchdog()
            dataTask = nil
            endBackgroundExecutionForCurrentRequest()
            return
        }
        if isToolContinuationStarting {
            dataTask = nil
            return
        }
        stopConnectionWatchdog()
        stopWatchdog()
        dataTask = nil

        let activeStyle = activeEndpointCandidate?.style ?? .openAIChatCompletions
        let completedCleanly = error == nil && httpStatusCode.map { (200...299).contains($0) } != false
        if activeStyle == .openAIChatCompletions, completedCleanly {
            flushOpenAIChatCompletionsPendingOutput()
        }
        let decision = ChatStreamCompletionRecovery.decide(
            isCancelled: isCancelled,
            httpStatusCode: httpStatusCode,
            error: error,
            errorResponseData: errorResponseData,
            successResponseData: successResponseData,
            sawAnyPrimaryAssistantToken: sawAnyPrimaryAssistantToken,
            hasPendingToolCalls: shouldRunToolLoopInsteadOfFinishing(),
            activeStyle: activeStyle,
            pendingLMStudioStreamErrorMessage: pendingLMStudioStreamErrorMessage,
            bufferedResponseParser: bufferedResponseParser,
            streamPayloadExtractor: streamPayloadExtractor
        )

        if let metadata = decision.metadata {
            mergeResponseMetadata(metadata)
        }

        switch decision.outcome {
        case .ignore:
            endBackgroundExecutionForCurrentRequest()
            return
        case .continueWithPendingTools:
            runPendingToolCallsAndContinue()
        case .finish:
            if shouldFinishWithBufferedPromptToolCall() {
                return
            }
            emitStreamFinishedOnce()
            if !isToolContinuationStarting {
                endBackgroundExecutionForCurrentRequest()
            }
        case let .recoveredText(text):
            if shouldRunRecoveredPromptToolCall(text) {
                return
            }
            emitRecoveredText(text, style: activeStyle)
            endBackgroundExecutionForCurrentRequest()
        case let .serverError(statusCode, message):
            let retryableError = statusCode.map { HTTPStatusError(statusCode: $0, bodyPreview: message) }
            if retryLMStudioRequestWithoutPreviousResponseIDIfNeeded(statusCode: statusCode, message: message) {
                return
            }
            if let retryableError, NetworkRetryability.shouldRetry(retryableError) {
                rememberLastRetryableActiveStreamRequest()
            }
            endBackgroundExecutionForCurrentRequest()
            clearActiveEndpointCandidate()
            deliverError(ChatNetworkError.serverError(statusCode: statusCode, message: message))
        case let .networkError(error):
            if NetworkRetryability.shouldRetry(error) {
                rememberLastRetryableActiveStreamRequest()
            }
            endBackgroundExecutionForCurrentRequest()
            clearActiveEndpointCandidate()
            deliverError(error)
        case .emptyResponse:
            endBackgroundExecutionForCurrentRequest()
            clearActiveEndpointCandidate()
            deliverError(ChatNetworkError.emptyResponse)
        }
    }

    @MainActor
    func retryLastFailedStreamRequest() -> Bool {
        var retryRequest: ChatRetryableStreamRequest?
        stateQueue.sync {
            retryRequest = lastRetryableStreamRequest
            lastRetryableStreamRequest = nil
        }
        guard let retryRequest else { return false }

        stateQueue.async { [weak self] in
            guard let self else { return }
            self.dataTask?.cancel()
            self.dataTask = nil
            self.stopWatchdog()
            self.resetStreamStateForActiveRequestRetry()
            self.advanceRequestGeneration()
            self.isCancelled = false
            self.activeEndpointCandidate = retryRequest.endpoint
            var retryContext = retryRequest.toolLoopContext
            retryContext?.requestGeneration = self.requestGeneration
            self.activeToolLoopContext = retryContext
            self.startStreaming(endpoint: retryRequest.endpoint, requestBodyData: retryRequest.body)
        }
        return true
    }

    func rememberLastRetryableActiveStreamRequest() {
        guard let endpoint = activeEndpointCandidate,
              let body = activeStreamRequestBodyData else {
            return
        }
        lastRetryableStreamRequest = ChatRetryableStreamRequest(
            endpoint: endpoint,
            body: body,
            toolLoopContext: activeToolLoopContext
        )
    }

    private func resetStreamStateForActiveRequestRetry() {
        beginStreamCallbackAttempt(invalidatingCurrentAttempt: true)
        dataTask = nil
        stopConnectionWatchdog()
        stopWatchdog()
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
        openAIResponsesOutputItems.removeAll(keepingCapacity: true)
        openAIChatCompletionsReasoningDetails.removeAll(keepingCapacity: true)
        openAIChatCompletionsReasoningText = ""
        pendingToolCalls.removeAll(keepingCapacity: true)
        toolCallAccumulator.reset()
        resetPromptToolGate()
        endBackgroundExecutionForCurrentRequest()
    }

    private func emitRecoveredText(_ text: String, style: ChatRequestStyle) {
        switch style {
        case .openAIResponses:
            emitSegment(.text(id: nil, text: text), marksPrimaryOutput: true)
            emitStreamFinishedOnce()
        case .openAIChatCompletions:
            var state = currentOpenAICompatibleStreamEventState()
            let actions = openAICompatibleStreamReducer.reduceRecoveredOutputText(text, state: &state)
            applyOpenAICompatibleStreamEventState(state)
            applyOpenAICompatibleStreamActions(actions)
        case .anthropicMessages, .lmStudioRESTV1:
            emitDelta(text)
            emitStreamFinishedOnce()
        }
    }

    private func shouldFinishWithBufferedPromptToolCall() -> Bool {
        guard shouldGatePromptTools() else { return false }
        return runBufferedPromptToolCallIfPresent()
    }

    private func shouldRunRecoveredPromptToolCall(_ text: String) -> Bool {
        guard shouldGatePromptTools() else { return false }
        let calls = ChatPromptToolProtocol.parseToolCalls(
            from: text,
            provider: activeEndpointCandidate?.provider
        )
        guard !calls.isEmpty else { return false }
        resetPromptToolGate()
        appendPendingToolCalls(calls)
        guard shouldRunToolLoopInsteadOfFinishing() else {
            emitStreamFinishedOnce()
            return true
        }
        runPendingToolCallsAndContinue()
        return true
    }

    static func isLMStudioMissingPreviousResponseError(statusCode: Int?, message: String) -> Bool {
        guard statusCode == 400 else { return false }
        let normalized = message.lowercased()
        if normalized.contains("previous_response_not_found") {
            return true
        }
        guard normalized.contains("previous_response_id") else { return false }
        return normalized.contains("could not find stored response") ||
            normalized.contains("automatically deleted") ||
            normalized.contains("invalid_value")
    }

    private func retryLMStudioRequestWithoutPreviousResponseIDIfNeeded(
        statusCode: Int?,
        message: String
    ) -> Bool {
        guard Self.isLMStudioMissingPreviousResponseError(statusCode: statusCode, message: message),
              var context = activeToolLoopContext,
              context.previousResponseID != nil,
              !context.didRetryWithoutPreviousResponseID else {
            return false
        }
        guard context.endpoint.style == .lmStudioRESTV1 else {
            return false
        }

        context.previousResponseID = nil
        context.didRetryWithoutPreviousResponseID = true
        do {
            let body = try requestBodyBuilder.buildRequestBodyData(
                model: context.model,
                messagePayload: context.currentPayload.messages,
                developerPrompt: context.developerPrompt,
                endpoint: context.endpoint,
                apiAdvancedSettings: configurationProvider.apiAdvancedSettings,
                toolUseSettings: configurationProvider.toolUseSettings,
                previousResponseID: nil,
                thinkingCapability: configurationProvider.thinkingCapability,
                thinkingOption: configurationProvider.thinkingOption
            )
            let requestContext = pendingResponseMetadata.requestContext
            resetStreamStateForActiveRequestRetry()
            activeToolLoopContext = context
            activeEndpointCandidate = context.endpoint
            isCancelled = false
            mergeResponseMetadata(ChatResponseMetadata(
                requestContext: requestContext,
                requestUsedPreviousResponseID: false
            ))
            startStreaming(endpoint: context.endpoint, requestBodyData: body)
            return true
        } catch {
            return false
        }
    }

}
