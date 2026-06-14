//
//  ChatService+StreamReducers.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension ChatService {
    func handleOpenAICompatibleStreamPayload(_ jsonData: Data, fallbackType: String?) -> Bool {
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
            isLegacyThinkStream: isLegacyThinkStream,
            sawAnyAssistantToken: sawAnyAssistantToken,
            sawAnyPrimaryAssistantToken: sawAnyPrimaryAssistantToken,
            newFormatActive: newFormatActive,
            sentThinkOpen: sentThinkOpen,
            sentThinkClose: sentThinkClose,
            lastProcessedSSESequenceNumber: lastProcessedSSESequenceNumber,
            reasoningDeltaItemIDs: reasoningDeltaItemIDs,
            outputTextDeltaItemIDs: outputTextDeltaItemIDs
        )
    }

    func applyOpenAICompatibleStreamEventState(_ state: OpenAICompatibleStreamEventState) {
        isLegacyThinkStream = state.isLegacyThinkStream
        sawAnyAssistantToken = state.sawAnyAssistantToken
        sawAnyPrimaryAssistantToken = state.sawAnyPrimaryAssistantToken
        newFormatActive = state.newFormatActive
        sentThinkOpen = state.sentThinkOpen
        sentThinkClose = state.sentThinkClose
        lastProcessedSSESequenceNumber = state.lastProcessedSSESequenceNumber
        reasoningDeltaItemIDs = state.reasoningDeltaItemIDs
        outputTextDeltaItemIDs = state.outputTextDeltaItemIDs
    }

    func applyOpenAICompatibleStreamActions(_ actions: [OpenAICompatibleStreamAction]) {
        for action in actions {
            switch action {
            case let .delta(piece, marksPrimaryOutput):
                emitDelta(piece, marksPrimaryOutput: marksPrimaryOutput)
            case let .metadata(metadata):
                mergeResponseMetadata(metadata)
            case .finish:
                emitStreamFinishedOnce()
                stopWatchdog()
            case let .fail(message):
                failCurrentStreamWithServerError(message)
            }
        }
    }

    func handleAnthropicStreamEvent(_ event: AnthropicStreamEvent) {
        guard !isCancelled else { return }
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
                emitStreamFinishedOnce()
                stopWatchdog()
            case let .fail(message):
                failCurrentStreamWithServerError(message, statusCode: nil, includeHTTPStatus: false)
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
            newFormatActive: newFormatActive,
            sentThinkOpen: sentThinkOpen,
            sentThinkClose: sentThinkClose,
            pendingStreamErrorMessage: pendingLMStudioStreamErrorMessage
        )
    }

    func applyLMStudioStreamEventState(_ state: LMStudioStreamEventState) {
        isLegacyThinkStream = state.isLegacyThinkStream
        sawAnyPrimaryAssistantToken = state.sawAnyPrimaryAssistantToken
        newFormatActive = state.newFormatActive
        sentThinkOpen = state.sentThinkOpen
        sentThinkClose = state.sentThinkClose
        pendingLMStudioStreamErrorMessage = state.pendingStreamErrorMessage
    }

    func applyLMStudioStreamActions(_ actions: [LMStudioStreamAction]) {
        for action in actions {
            switch action {
            case let .delta(piece, marksPrimaryOutput):
                emitDelta(piece, marksPrimaryOutput: marksPrimaryOutput)
            case let .metadata(metadata):
                mergeResponseMetadata(metadata)
            case .finish:
                emitStreamFinishedOnce()
                stopWatchdog()
            case let .fail(message):
                failCurrentStreamWithServerError(message)
                stopWatchdog()
            }
        }
    }
}
