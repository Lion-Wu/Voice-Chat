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
        guard let activeRequest = activeStreamRequest, dataTask === activeRequest.task else {
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
        guard let activeRequest = activeStreamRequest, task === activeRequest.task else { return }
        guard totalBytesSent > 0 else { return }
        markConnectionEstablishedIfNeeded()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let activeRequest = activeStreamRequest, dataTask === activeRequest.task else { return }
        guard !isCancelled else { return }
        let activeEndpoint = activeRequest.endpoint
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
            failCurrentStream(with: ChatNetworkError.serverError(
                statusCode: nil,
                message: NSLocalizedString("Stream payload exceeded safety limit", comment: "Shown when streamed SSE data exceeds the configured memory safety cap")
            ))
            return
        }

        for frame in frames {
            guard !isCancelled,
                  activeStreamRequest?.task === activeRequest.task else { return }
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
            let activeStyle = activeEndpoint.style

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
        guard let activeRequest = activeStreamRequest, task === activeRequest.task else { return }
        stopWatchdog()
        let activeEndpoint = activeRequest.endpoint
        let activeStyle = activeEndpoint.style
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
            activeStreamRequest = nil
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
            if retryLMStudioRequestWithoutPreviousResponseIDIfNeeded(statusCode: statusCode, message: message) {
                return
            }
            failCurrentStream(with: ChatNetworkError.serverError(statusCode: statusCode, message: message))
        case let .networkError(error):
            failCurrentStream(with: error)
        case .emptyResponse:
            failCurrentStream(with: ChatNetworkError.emptyResponse)
        }
    }

    @MainActor
    func cancelActiveStreamForManualRetry() -> Bool {
        stateQueue.sync {
            guard activeStreamRequest != nil else { return false }

            isCancelled = true
            advanceRequestGeneration()
            beginStreamCallbackAttempt(invalidatingCurrentAttempt: true)
            updateLongWaitNotice(nil)
            activeStreamRequest?.task.cancel()
            activeStreamRequest = nil
            cancelActiveToolExecution()
            stopWatchdog()
            activeToolLoopContext = nil
            Task { await toolAuthorizationCoordinator.cancelAll() }
            endBackgroundExecutionForCurrentRequest()
            return true
        }
    }

    private func resetStreamStateForActiveRequestRetry() {
        beginStreamCallbackAttempt(invalidatingCurrentAttempt: true)
        activeStreamRequest?.task.cancel()
        activeStreamRequest = nil
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
        updateLongWaitNotice(nil)
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
            provider: activeStreamRequest?.endpoint.provider
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
