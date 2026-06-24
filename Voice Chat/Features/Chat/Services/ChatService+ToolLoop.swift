//
//  ChatService+ToolLoop.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

extension ChatService {
    func collectOpenAIToolCalls(from jsonData: Data) {
        guard configurationProvider.toolUseSettings.isEnabled,
              let object = try? JSONSerialization.jsonObject(with: jsonData),
              let dictionary = object as? [String: Any] else {
            return
        }
        let calls = toolCallAccumulator.absorbOpenAICompatiblePayload(
            dictionary,
            provider: activeEndpointCandidate?.provider
        )
        appendPendingToolCalls(calls)
    }

    func collectAnthropicToolCalls(from event: AnthropicStreamEvent) {
        guard configurationProvider.toolUseSettings.isEnabled else { return }
        let calls = toolCallAccumulator.absorbAnthropicEvent(
            event,
            provider: activeEndpointCandidate?.provider
        )
        appendPendingToolCalls(calls)
    }

    func shouldRunToolLoopInsteadOfFinishing() -> Bool {
        appendPendingToolCalls(toolCallAccumulator.drain(provider: activeEndpointCandidate?.provider))
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
        toolCallAccumulator.reset()

        guard !calls.isEmpty else {
            emitStreamFinishedOnce()
            return
        }

        stopWatchdog()
        stopConnectionWatchdog()
        dataTask = nil

        Task { [weak self] in
            guard let self else { return }
            let results = await self.executeToolCalls(calls, endpoint: context.endpoint)
            await self.continueAfterToolResults(calls: calls, results: results, context: context)
        }
    }

    private func executeToolCalls(
        _ calls: [ChatToolCallEnvelope],
        endpoint: ChatAPIEndpointCandidate
    ) async -> [ChatToolResultEnvelope] {
        var results: [ChatToolResultEnvelope] = []
        results.reserveCapacity(calls.count)

        for call in calls {
            let title = ChatToolDefinitions.activityTitle(for: call.name)
            emitToolActivity(.init(id: call.callID, toolName: call.name, title: title, phase: .requested))
            emitToolActivity(.init(id: call.callID, toolName: call.name, title: title, phase: .running))
            let result = await toolExecutor.execute(
                call,
                settings: configurationProvider.toolUseSettings,
                endpoint: endpoint
            )
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
                summary: result.summary
            ))
        }
        return results
    }

    private func continueAfterToolResults(
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope],
        context: ChatToolLoopContext
    ) async {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                guard !self.isCancelled else {
                    continuation.resume()
                    return
                }

                var nextContext = context
                nextContext.iteration += 1
                let providerResponseID = self.pendingResponseMetadata.providerResponseID ?? context.previousResponseID
                nextContext.previousResponseID = ChatToolResultMessageEncoder.previousResponseIDForToolContinuation(
                    providerResponseID,
                    endpoint: context.endpoint
                )
                self.activeToolLoopContext = nextContext

                let nextPayload = ChatToolResultMessageEncoder.followUpPayload(
                    for: context.endpoint,
                    originalPayload: context.currentPayload.messages,
                    calls: calls,
                    results: results
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
                    self.activeToolLoopContext = nextContext
                    self.activeEndpointCandidate = context.endpoint
                    self.startStreaming(endpoint: context.endpoint, requestBodyData: body)
                } catch {
                    self.failCurrentStreamWithServerError(error.localizedDescription)
                }
                continuation.resume()
            }
        }
    }

    private func resetStreamStateForToolContinuation() {
        isLegacyThinkStream = false
        sawAnyAssistantToken = false
        sawAnyPrimaryAssistantToken = false
        newFormatActive = false
        sentThinkOpen = false
        sentThinkClose = false
        streamFinishedEmitted = false
        lastProcessedSSESequenceNumber = nil
        reasoningDeltaItemIDs.removeAll(keepingCapacity: true)
        outputTextDeltaItemIDs.removeAll(keepingCapacity: true)
        anthropicStreamState = .init()
        sseParser.reset()
        streamStartAt = nil
        didEstablishConnection = false
        lastDeltaAt = nil
        httpStatusCode = nil
        errorResponseData.removeAll(keepingCapacity: true)
        successResponseData.removeAll(keepingCapacity: true)
        pendingLMStudioStreamErrorMessage = nil
        pendingResponseMetadata = .empty
        pendingToolCalls.removeAll(keepingCapacity: true)
        toolCallAccumulator.reset()
        resetLMStudioPromptToolGate(preservingOpenThinking: lmStudioPromptToolKeepsThinkOpen)
        stopConnectionWatchdog()
        endBackgroundExecutionForCurrentRequest()
    }

    func appendPendingToolCalls(_ calls: [ChatToolCallEnvelope]) {
        guard !calls.isEmpty else { return }
        for call in calls where !pendingToolCalls.contains(where: { $0.callID == call.callID }) {
            pendingToolCalls.append(call)
        }
    }

}
