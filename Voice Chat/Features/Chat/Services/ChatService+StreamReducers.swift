//
//  ChatService+StreamReducers.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension ChatService {
    func handleOpenAICompatibleStreamPayload(_ jsonData: Data, fallbackType: String?) -> Bool {
        if activeEndpointCandidate?.style == .openAIResponses {
            if let object = try? JSONSerialization.jsonObject(with: jsonData),
               let dictionary = object as? [String: Any],
               let sequenceNumber = streamPayloadExtractor.sseSequenceNumber(from: dictionary),
               let lastProcessed = openAIResponsesStreamItemState.lastProcessedSSESequenceNumber,
               sequenceNumber <= lastProcessed {
                return true
            }
            collectOpenAIResponsesOutputItems(from: jsonData, fallbackType: fallbackType)
            collectOpenAIToolCalls(from: jsonData, fallbackType: fallbackType)
            var state = openAIResponsesStreamItemState
            let reduction = openAIResponsesStreamItemReducer.reduce(
                jsonData: jsonData,
                fallbackType: fallbackType,
                state: &state
            )
            openAIResponsesStreamItemState = state
            applyOpenAICompatibleStreamActions(reduction.actions)
            return reduction.handled
        }

        collectOpenAIToolCalls(from: jsonData, fallbackType: fallbackType)
        var state = currentOpenAICompatibleStreamEventState()
        let reduction = openAICompatibleStreamReducer.reduce(
            jsonData: jsonData,
            fallbackType: fallbackType,
            state: &state
        )
        applyOpenAICompatibleStreamEventState(state)
        applyOpenAICompatibleStreamActions(reduction.actions)
        return reduction.handled
    }

    func currentOpenAICompatibleStreamEventState() -> OpenAICompatibleStreamEventState {
        OpenAICompatibleStreamEventState(
            sawAnyAssistantToken: sawAnyAssistantToken,
            sawAnyPrimaryAssistantToken: sawAnyPrimaryAssistantToken,
            isInsideLegacyThinkTag: isInsideLegacyThinkTag,
            shouldTrimNextLegacyThinkLeadingNewline: shouldTrimNextLegacyThinkLeadingNewline,
            legacyThinkTagBuffer: legacyThinkTagBuffer,
            lastProcessedSSESequenceNumber: lastProcessedSSESequenceNumber,
            reasoningDeltaItemIDs: reasoningDeltaItemIDs,
            outputTextDeltaItemIDs: outputTextDeltaItemIDs
        )
    }

    func applyOpenAICompatibleStreamEventState(_ state: OpenAICompatibleStreamEventState) {
        sawAnyAssistantToken = state.sawAnyAssistantToken
        sawAnyPrimaryAssistantToken = state.sawAnyPrimaryAssistantToken
        isInsideLegacyThinkTag = state.isInsideLegacyThinkTag
        shouldTrimNextLegacyThinkLeadingNewline = state.shouldTrimNextLegacyThinkLeadingNewline
        legacyThinkTagBuffer = state.legacyThinkTagBuffer
        lastProcessedSSESequenceNumber = state.lastProcessedSSESequenceNumber
        reasoningDeltaItemIDs = state.reasoningDeltaItemIDs
        outputTextDeltaItemIDs = state.outputTextDeltaItemIDs
    }

    func flushOpenAIChatCompletionsPendingOutput() {
        guard activeEndpointCandidate?.style == .openAIChatCompletions else { return }
        var state = currentOpenAICompatibleStreamEventState()
        let actions = openAICompatibleStreamReducer.flushPendingOutput(state: &state)
        applyOpenAICompatibleStreamEventState(state)
        applyOpenAICompatibleStreamActions(actions)
    }

    func applyOpenAICompatibleStreamActions(_ actions: [OpenAICompatibleStreamAction]) {
        for action in actions {
            switch action {
            case let .delta(piece, marksPrimaryOutput):
                handlePromptToolDelta(piece, marksPrimaryOutput: marksPrimaryOutput)
            case let .segment(segment, marksPrimaryOutput):
                emitSegment(segment, marksPrimaryOutput: marksPrimaryOutput)
            case let .metadata(metadata):
                mergeResponseMetadata(metadata)
            case .finish:
                finishStreamOrRunPendingTools()
            case let .incomplete(message, segments):
                failCurrentStream(with: ChatIncompleteResponseError(
                    message: message,
                    segments: segments,
                    metadata: pendingResponseMetadata
                ))
            case let .fail(message):
                failCurrentStreamWithServerError(message)
            case let .retryableFailure(message, statusCode):
                rememberLastRetryableActiveStreamRequest()
                failCurrentStreamWithServerError(message, statusCode: statusCode)
            }
        }
    }

    func handleAnthropicStreamEvent(_ event: AnthropicStreamEvent) {
        guard !isCancelled else { return }
        anthropicAssistantContentAccumulator.absorb(event)
        collectAnthropicToolCalls(from: event)
        var state = anthropicStreamState
        let actions = anthropicStreamReducer.reduce(event, state: &state)
        anthropicStreamState = state
        sentThinkOpen = state.sentThinkOpen
        sentThinkClose = state.sentThinkClose
        applyAnthropicStreamActions(actions)
    }

    func applyAnthropicStreamActions(_ actions: [AnthropicStreamAction]) {
        for action in actions {
            switch action {
            case let .delta(piece, marksPrimaryOutput):
                emitDelta(piece, marksPrimaryOutput: marksPrimaryOutput)
            case let .metadata(metadata):
                mergeResponseMetadata(metadata)
            case .finish:
                handlePromptToolFinish()
                stopWatchdog()
            case let .fail(message):
                failCurrentStreamWithServerError(message, statusCode: nil, includeHTTPStatus: false)
            case let .retryableFailure(message, statusCode):
                rememberLastRetryableActiveStreamRequest()
                failCurrentStreamWithServerError(message, statusCode: statusCode, includeHTTPStatus: false)
            }
        }
    }

    func handleLMStudioStreamEvent(_ event: LMStudioChatStreamEvent, fallbackType: String? = nil) {
        guard !isCancelled else { return }
        var state = currentLMStudioStreamEventState()
        let actions = lmStudioStreamReducer.reduce(event, fallbackType: fallbackType, state: &state)
        applyLMStudioStreamEventState(state)
        applyLMStudioStreamActions(actions)
    }

    func currentLMStudioStreamEventState() -> LMStudioStreamEventState {
        LMStudioStreamEventState(
            isLegacyThinkStream: isLegacyThinkStream,
            sawAnyPrimaryAssistantToken: sawAnyPrimaryAssistantToken,
            sawAnyReasoningToken: lmStudioSawAnyReasoningToken,
            newFormatActive: newFormatActive,
            sentThinkOpen: sentThinkOpen,
            sentThinkClose: sentThinkClose,
            pendingStreamErrorMessage: pendingLMStudioStreamErrorMessage
        )
    }

    func applyLMStudioStreamEventState(_ state: LMStudioStreamEventState) {
        isLegacyThinkStream = state.isLegacyThinkStream
        sawAnyPrimaryAssistantToken = state.sawAnyPrimaryAssistantToken
        lmStudioSawAnyReasoningToken = state.sawAnyReasoningToken
        newFormatActive = state.newFormatActive
        sentThinkOpen = state.sentThinkOpen
        sentThinkClose = state.sentThinkClose
        pendingLMStudioStreamErrorMessage = state.pendingStreamErrorMessage
    }

    func applyLMStudioStreamActions(_ actions: [LMStudioStreamAction]) {
        for action in actions {
            switch action {
            case let .delta(piece, marksPrimaryOutput):
                handlePromptToolDelta(piece, marksPrimaryOutput: marksPrimaryOutput)
            case let .metadata(metadata):
                mergeResponseMetadata(metadata)
            case .finish:
                handlePromptToolFinish()
            case let .fail(message):
                failCurrentStreamWithServerError(message)
                stopWatchdog()
            case let .retryableFailure(message, statusCode):
                rememberLastRetryableActiveStreamRequest()
                failCurrentStreamWithServerError(message, statusCode: statusCode)
                stopWatchdog()
            }
        }
    }
}
