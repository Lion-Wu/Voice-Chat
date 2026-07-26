//
//  ChatService+ToolLoop.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

extension ChatService {
    func collectOpenAIToolCalls(from jsonData: Data, fallbackType: String?) {
        guard configurationProvider.toolUseSettings.isEnabled,
              let object = try? JSONSerialization.jsonObject(with: jsonData),
              let dictionary = object as? [String: Any] else {
            return
        }
        if activeEndpointCandidate?.style == .openAIChatCompletions,
           let chunk = try? decoder.decode(ChatCompletionChunk.self, from: jsonData) {
            let details = chunk.choices?
                .flatMap { $0.delta?.reasoning_details ?? [] } ?? []
            openAIChatCompletionsReasoningDetails.append(contentsOf: details)
            for choice in chunk.choices ?? [] {
                guard let delta = choice.delta else { continue }
                if let reasoning = delta.reasoning?.text, !reasoning.isEmpty {
                    openAIChatCompletionsReasoningText += reasoning
                } else if let reasoning = delta.reasoning_content, !reasoning.isEmpty {
                    openAIChatCompletionsReasoningText += reasoning
                }
            }
        }
        let calls = toolCallAccumulator.absorbOpenAICompatiblePayload(
            dictionary,
            fallbackType: fallbackType,
            provider: activeEndpointCandidate?.provider
        )
        emitGeneratingToolActivities(
            toolCallAccumulator.inProgressCalls(provider: activeEndpointCandidate?.provider)
        )
        appendPendingToolCalls(calls)
    }

    func collectOpenAIResponsesOutputItems(from jsonData: Data, fallbackType: String?) {
        guard let endpoint = activeEndpointCandidate,
              endpoint.style == .openAIResponses,
              let object = try? JSONSerialization.jsonObject(with: jsonData),
              let dictionary = object as? [String: Any] else {
            return
        }

        let eventType = ((dictionary["type"] as? String) ?? fallbackType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch eventType {
        case "response.output_item.done":
            if let item = dictionary["item"] as? [String: Any] {
                appendOpenAIResponsesOutputItem(item)
            }
        case "response.completed", "response.done", "":
            if let response = dictionary["response"] as? [String: Any],
               let output = response["output"] as? [[String: Any]] {
                replaceOpenAIResponsesOutputItems(with: output)
            } else if let output = dictionary["output"] as? [[String: Any]] {
                replaceOpenAIResponsesOutputItems(with: output)
            }
        default:
            break
        }
    }

    func collectAnthropicToolCalls(from event: AnthropicStreamEvent) {
        guard configurationProvider.toolUseSettings.isEnabled else { return }
        let calls = toolCallAccumulator.absorbAnthropicEvent(
            event,
            provider: activeEndpointCandidate?.provider
        )
        emitGeneratingToolActivities(
            toolCallAccumulator.inProgressCalls(provider: activeEndpointCandidate?.provider)
        )
        appendPendingToolCalls(calls)
    }

    func shouldRunToolLoopInsteadOfFinishing() -> Bool {
        guard configurationProvider.toolUseSettings.isEnabled,
              !pendingToolCalls.isEmpty,
              activeToolLoopContext != nil else {
            return false
        }
        return true
    }

    func runPendingToolCallsAndContinue() {
        guard let context = activeToolLoopContext else { return }
        let calls = pendingToolCalls
        pendingToolCalls.removeAll(keepingCapacity: true)
        generatingToolActivities.removeAll(keepingCapacity: true)
        toolCallAccumulator.reset()

        guard !calls.isEmpty else {
            emitStreamFinishedOnce()
            return
        }
        stopWatchdog()
        stopConnectionWatchdog()
        dataTask?.cancel()
        dataTask = nil
        activeStreamRequestBodyData = nil
        lastRetryableStreamRequest = nil
        isToolContinuationStarting = true

        cancelActiveToolExecution()
        let executionID = UUID()
        activeToolExecutionID = executionID
        activeToolExecutionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.stateQueue.async { [weak self] in
                    guard let self, self.activeToolExecutionID == executionID else { return }
                    self.activeToolExecutionID = nil
                    self.activeToolExecutionTask = nil
                }
            }
            let results = await self.executeToolCalls(calls, context: context)
            guard !Task.isCancelled,
                  await self.isCurrentRequestGenerationAsync(context.requestGeneration) else { return }
            await self.continueAfterToolResults(calls: calls, results: results, context: context)
        }
    }

    private func executeToolCalls(
        _ calls: [ChatToolCallEnvelope],
        context: ChatToolLoopContext
    ) async -> [ChatToolResultEnvelope] {
        var results: [ChatToolResultEnvelope] = []
        results.reserveCapacity(calls.count)

        for call in calls {
            guard !Task.isCancelled,
                  await isCurrentRequestGenerationAsync(context.requestGeneration) else { return results }
            let title = ChatToolDefinitions.activityTitle(for: call.name)
            let argumentSummary = ChatToolDefinitions.activitySummary(for: call)
            let modelRequestPayload = modelRequestPayload(for: call)
            emitToolActivity(.init(
                id: call.callID,
                toolName: call.name,
                title: title,
                phase: .requested,
                summary: argumentSummary,
                modelRequestPayload: modelRequestPayload
            ), requestGeneration: context.requestGeneration)
            if let authorizationFailure = await authorizeToolCallIfNeeded(
                call,
                title: title,
                endpoint: context.endpoint,
                requestGeneration: context.requestGeneration
            ) {
                guard !Task.isCancelled,
                      await isCurrentRequestGenerationAsync(context.requestGeneration) else { return results }
                results.append(authorizationFailure)
                emitToolActivity(.init(
                    id: call.callID,
                    toolName: call.name,
                    title: title,
                    phase: .denied,
                    summary: ChatToolDefinitions.activitySummary(
                        for: call,
                        resultSummary: authorizationFailure.summary
                    ),
                    modelRequestPayload: modelRequestPayload,
                    resultPayload: authorizationFailure.payload
                ), requestGeneration: context.requestGeneration)
                continue
            }
            guard !Task.isCancelled,
                  await isCurrentRequestGenerationAsync(context.requestGeneration) else { return results }
            emitToolActivity(.init(
                id: call.callID,
                toolName: call.name,
                title: title,
                phase: .running,
                summary: argumentSummary,
                modelRequestPayload: modelRequestPayload
            ), requestGeneration: context.requestGeneration)
            let result = await toolExecutor.execute(
                call,
                settings: configurationProvider.toolUseSettings,
                endpoint: context.endpoint
            )
            guard !Task.isCancelled,
                  await isCurrentRequestGenerationAsync(context.requestGeneration) else { return results }
            results.append(result)
            let phase: ChatToolActivityPhase
            switch result.status {
            case .success:
                phase = .succeeded
            case .denied:
                phase = .denied
            case .unsupported:
                phase = .unsupported
            case .invalidArguments, .failed:
                phase = .failed
            }
            emitToolActivity(.init(
                id: call.callID,
                toolName: call.name,
                title: title,
                phase: phase,
                summary: ChatToolDefinitions.activitySummary(
                    for: call,
                    resultSummary: result.summary
                ),
                presentation: result.presentation,
                modelRequestPayload: modelRequestPayload,
                resultPayload: result.payload
            ), requestGeneration: context.requestGeneration)
        }
        return results
    }

    private func authorizeToolCallIfNeeded(
        _ call: ChatToolCallEnvelope,
        title: String,
        endpoint: ChatAPIEndpointCandidate,
        requestGeneration: UInt64
    ) async -> ChatToolResultEnvelope? {
        guard let toolID = call.toolID else { return nil }
        let settings = configurationProvider.toolUseSettings
        guard settings.enabledToolIDs.contains(toolID) else {
            return ChatToolResultEnvelope(
                callID: call.callID,
                name: call.name,
                status: .denied,
                payload: ["error": .string(NSLocalizedString("This tool is disabled for the current endpoint.", comment: "Tool-use error"))],
                summary: NSLocalizedString("This tool is disabled for the current endpoint.", comment: "Tool-use error")
            )
        }
        let decision = ChatToolAuthorizationPolicy.decision(
            for: toolID,
            settings: settings,
            endpoint: endpoint
        )
        switch decision {
        case .allow:
            return nil
        case let .deny(message):
            return ChatToolResultEnvelope(
                callID: call.callID,
                name: call.name,
                status: .denied,
                payload: ["error": .string(message)],
                summary: message
            )
        case .ask:
            break
        }

        let request = ChatToolAuthorizationRequest(
            id: "\(requestGeneration):\(call.callID):\(UUID().uuidString)",
            toolName: call.name,
            title: title,
            operationKind: toolID.operationKind,
            argumentsSummary: call.argumentsJSON
        )
        emitToolActivity(.init(
            id: call.callID,
            toolName: call.name,
            title: title,
            phase: .authorizing,
            summary: ChatToolDefinitions.activitySummary(
                for: call,
                resultSummary: NSLocalizedString("Waiting for approval.", comment: "Tool activity summary")
            ),
            authorizationRequest: request,
            modelRequestPayload: modelRequestPayload(for: call)
        ), requestGeneration: requestGeneration)
        let allowed = await toolAuthorizationCoordinator.waitForDecision(requestID: request.id)
        guard allowed else {
            return ChatToolResultEnvelope(
                callID: call.callID,
                name: call.name,
                status: .denied,
                payload: ["error": .string(NSLocalizedString("Tool call was denied by the user.", comment: "Tool-use error"))],
                summary: NSLocalizedString("Tool call was denied by the user.", comment: "Tool-use error")
            )
        }
        return nil
    }

    private func continueAfterToolResults(
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope],
        context: ChatToolLoopContext
    ) async {
        await drainToolCallbacksBeforeContinuation()
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                guard self.isCurrentRequestGeneration(context.requestGeneration) else {
                    continuation.resume()
                    return
                }

                var nextContext = context
                nextContext.iteration += 1
                nextContext.previousResponseID = self.configurationProvider.toolUseSettings.useProviderContinuationIDs(for: context.endpoint)
                    ? Self.previousResponseIDForToolContinuation(
                        providerResponseIDFromToolCallResponse: self.pendingResponseMetadata.providerResponseID,
                        endpoint: context.endpoint,
                        settings: self.configurationProvider.toolUseSettings
                    )
                    : nil
                self.activeToolLoopContext = nextContext
                self.recordOpenAIResponsesToolExchangeIfNeeded(calls: calls, results: results)
                let nextPayload = ChatToolResultMessageEncoder.followUpPayload(
                    for: context.endpoint,
                    originalPayload: context.currentPayload.messages,
                    calls: calls,
                    results: results,
                    previousResponseID: nextContext.previousResponseID,
                    responsesOutputItems: self.openAIResponsesOutputItems,
                    anthropicContentBlocks: self.anthropicAssistantContentAccumulator.contentBlocks,
                    chatCompletionsReasoningDetails: self.openAIChatCompletionsReasoningDetails,
                    chatCompletionsReasoning: self.openAIChatCompletionsReasoningText
                )
                nextContext.currentPayload = ChatToolLoopPayload(messages: nextPayload)
                do {
                    let body = try self.requestBodyBuilder.buildRequestBodyData(
                        model: context.model,
                        messagePayload: nextPayload,
                        developerPrompt: context.developerPrompt,
                        endpoint: context.endpoint,
                        apiAdvancedSettings: self.configurationProvider.apiAdvancedSettings,
                        toolUseSettings: self.configurationProvider.toolUseSettings,
                        previousResponseID: nextContext.previousResponseID,
                        thinkingCapability: self.configurationProvider.thinkingCapability,
                        thinkingOption: self.configurationProvider.thinkingOption
                    )
                    self.resetStreamStateForToolContinuation()
                    self.emitToolContinuationProcessingActivity(for: calls)
                    self.activeToolLoopContext = nextContext
                    self.activeEndpointCandidate = context.endpoint
                    self.mergeResponseMetadata(ChatResponseMetadata(
                        requestUsedPreviousResponseID: nextContext.previousResponseID != nil,
                        requestPreviousResponseID: nextContext.previousResponseID
                    ))
                    self.startStreaming(endpoint: context.endpoint, requestBodyData: body)
                } catch {
                    if self.isCurrentRequestGeneration(context.requestGeneration) {
                        self.failCurrentStreamWithServerError(error.localizedDescription)
                    }
                }
                continuation.resume()
            }
        }
    }

    private func drainToolCallbacksBeforeContinuation() async {
        await withCheckedContinuation { continuation in
            stateQueue.async {
                continuation.resume()
            }
        }
        await MainActor.run {}
    }

    private func modelRequestPayload(for call: ChatToolCallEnvelope) -> [String: JSONValue] {
        var payload: [String: JSONValue] = [
            "call_id": .string(call.callID),
            "tool": .string(call.name),
            "arguments_json": .string(call.argumentsJSON)
        ]
        if let provider = call.provider {
            payload["provider"] = .string(provider.rawValue)
        }
        if let data = call.argumentsJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: []) {
            payload["arguments"] = JSONValue.normalized(object)
        }
        return payload
    }

    private func emitToolContinuationProcessingActivity(for calls: [ChatToolCallEnvelope]) {
        guard let lastCall = calls.last else { return }
        emitToolActivity(.init(
            id: "\(lastCall.callID)-continuation",
            toolName: lastCall.name,
            title: ChatToolDefinitions.activityTitle(for: lastCall.name),
            phase: .processing
        ))
    }

    private func resetStreamStateForToolContinuation() {
        // A tool continuation starts a new stream stage, but the completed stage's
        // queued callbacks (notably its persisted function-call output) remain valid.
        // Failed HTTP retries use the invalidating reset path instead.
        beginStreamCallbackAttempt(invalidatingCurrentAttempt: false)
        let shouldPreserveOpenAIThinking = newFormatActive &&
            sentThinkOpen &&
            !sentThinkClose &&
            !isLegacyThinkStream
        isLegacyThinkStream = false
        sawAnyAssistantToken = false
        sawAnyPrimaryAssistantToken = false
        lmStudioSawAnyReasoningToken = false
        newFormatActive = shouldPreserveOpenAIThinking
        sentThinkOpen = shouldPreserveOpenAIThinking
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
        resetPromptToolGate(preservingOpenThinking: promptToolKeepsThinkOpen)
        stopConnectionWatchdog()
        endBackgroundExecutionForCurrentRequest()
    }

    func appendPendingToolCalls(_ calls: [ChatToolCallEnvelope]) {
        guard !calls.isEmpty else { return }
        for call in calls {
            generatingToolActivities[call.callID] = nil
            if !pendingToolCalls.contains(where: { $0.callID == call.callID }) {
                pendingToolCalls.append(call)
            }
        }
    }

    private func emitGeneratingToolActivities(_ calls: [ChatToolCallEnvelope]) {
        for call in calls where call.toolID != nil {
            let activity = ChatToolActivity(
                id: call.callID,
                toolName: call.name,
                title: ChatToolDefinitions.activityTitle(for: call.name),
                phase: .generating,
                summary: ChatToolDefinitions.activitySummary(for: call)
            )
            guard generatingToolActivities[call.callID] != activity else { continue }
            generatingToolActivities[call.callID] = activity
            emitToolActivity(activity)
        }
    }

    func resolveToolAuthorization(requestID: String, allowed: Bool) {
        Task { await toolAuthorizationCoordinator.resolve(requestID: requestID, allowed: allowed) }
    }

    static func previousResponseIDForToolContinuation(
        providerResponseIDFromToolCallResponse: String?,
        endpoint: ChatAPIEndpointCandidate,
        settings: ToolUseSettings
    ) -> String? {
        ChatToolResultMessageEncoder.previousResponseIDForToolContinuation(
            providerResponseIDFromToolCallResponse,
            endpoint: endpoint,
            settings: settings
        )
    }

    private func appendOpenAIResponsesOutputItem(_ item: [String: Any]) {
        let type = ((item["type"] as? String) ?? "").lowercased()
        guard type == "reasoning" || type == "message" || type == "function_call" else { return }
        let key = openAIResponsesOutputItemKey(item)
        guard !openAIResponsesOutputItems.contains(where: { openAIResponsesOutputItemKey($0) == key }) else {
            return
        }
        openAIResponsesOutputItems.append(item)
    }

    private func replaceOpenAIResponsesOutputItems(with items: [[String: Any]]) {
        openAIResponsesOutputItems.removeAll(keepingCapacity: true)
        items.forEach(appendOpenAIResponsesOutputItem)
    }

    func recordCurrentOpenAIResponsesOutputItemsIfNeeded() {
        guard activeEndpointCandidate?.style == .openAIResponses else { return }
        let previousCount = openAIResponsesConversationItems.count
        for item in openAIResponsesOutputItems {
            appendOpenAIResponsesConversationItem(item)
        }
        guard openAIResponsesConversationItems.count != previousCount else { return }
        deliverOpenAIResponsesConversationItems(openAIResponsesConversationItems)
    }

    private func recordOpenAIResponsesToolExchangeIfNeeded(
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope]
    ) {
        guard activeEndpointCandidate?.style == .openAIResponses else { return }
        for call in calls {
            appendOpenAIResponsesConversationItem([
                "type": "function_call",
                "id": call.itemID ?? call.callID,
                "call_id": call.callID,
                "name": call.name,
                "arguments": call.argumentsJSON
            ])
        }
        for result in results {
            appendOpenAIResponsesConversationItem([
                "type": "function_call_output",
                "call_id": result.callID,
                "output": result.outputJSONString
            ])
        }
        deliverOpenAIResponsesConversationItems(openAIResponsesConversationItems)
    }

    private func appendOpenAIResponsesConversationItem(_ item: [String: Any]) {
        let type = ((item["type"] as? String) ?? "").lowercased()
        guard ["reasoning", "message", "function_call", "function_call_output"].contains(type) else {
            return
        }
        let key = openAIResponsesOutputItemKey(item)
        guard !openAIResponsesConversationItems.contains(where: { value in
            guard let existing = value.jsonObject as? [String: Any] else { return false }
            return openAIResponsesOutputItemKey(existing) == key
        }) else {
            return
        }
        openAIResponsesConversationItems.append(.normalized(item))
    }

    private func openAIResponsesOutputItemKey(_ item: [String: Any]) -> String {
        let type = ((item["type"] as? String) ?? "").lowercased()
        if let id = item["id"] as? String, !id.isEmpty {
            return "\(type):id:\(id)"
        }
        if let callID = item["call_id"] as? String, !callID.isEmpty {
            return "\(type):call_id:\(callID)"
        }
        if JSONSerialization.isValidJSONObject(item),
           let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return "\(type):json:\(json)"
        }
        return type
    }

}
