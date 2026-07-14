//
//  AnthropicStreamEventReducer.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct AnthropicStreamEventState: Equatable {
    var thinkingActive = false
    var sentThinkOpen = false
    var sentThinkClose = false
}

enum AnthropicStreamAction: Equatable {
    case delta(String, marksPrimaryOutput: Bool)
    case metadata(ChatResponseMetadata)
    case finish
    case fail(String)
    case retryableFailure(String, statusCode: Int)
}

struct AnthropicStreamEventReducer {
    private let thinkOpenLine = "<think>\n"
    private let thinkCloseLine = "\n</think>\n"

    func reduce(
        _ event: AnthropicStreamEvent,
        state: inout AnthropicStreamEventState
    ) -> [AnthropicStreamAction] {
        guard let rawType = event.type?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty else {
            return []
        }

        var actions: [AnthropicStreamAction] = []
        let metadata = metadata(from: event)
        if metadata.hasAnyValue {
            actions.append(.metadata(metadata))
        }

        switch rawType.lowercased() {
        case "content_block_start":
            reduceContentBlockStart(event, state: &state, actions: &actions)

        case "content_block_delta":
            reduceContentBlockDelta(event, state: &state, actions: &actions)

        case "content_block_stop":
            closeThinkingIfNeeded(state: &state, actions: &actions)

        case "message_stop":
            closeThinkingIfNeeded(state: &state, actions: &actions)
            actions.append(.finish)

        case "error":
            let message = event.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedMessage = (message?.isEmpty == false) ? message! : NSLocalizedString(
                "Anthropic API error",
                comment: "Fallback error shown when Anthropic stream returns an error event without a message"
            )
            if let statusCode = ChatStreamErrorRetryClassifier.statusCode(for: [event.error?.type]) {
                actions.append(.retryableFailure(resolvedMessage, statusCode: statusCode))
            } else {
                actions.append(.fail(resolvedMessage))
            }

        default:
            break
        }

        return actions
    }

    private func metadata(from event: AnthropicStreamEvent) -> ChatResponseMetadata {
        var metadata = ChatResponseMetadata.empty
        if let responseID = event.message?.id,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.providerResponseID = responseID
        }
        let usage = event.usage ?? event.message?.usage
        if let usage {
            metadata.outputTokenCount = usage.output_tokens
            metadata.reasoningOutputTokenCount = usage.output_tokens_details?.thinking_tokens
                ?? usage.output_tokens_details?.reasoning_tokens
        }
        if let stopReason = event.delta?.stop_reason ?? event.message?.stop_reason,
           !stopReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.finishReason = stopReason
        }
        return metadata
    }

    private func reduceContentBlockStart(
        _ event: AnthropicStreamEvent,
        state: inout AnthropicStreamEventState,
        actions: inout [AnthropicStreamAction]
    ) {
        let blockType = (event.content_block?.type ?? "").lowercased()
        if blockType.contains("thinking") {
            openThinkingIfNeeded(state: &state, actions: &actions)
            state.thinkingActive = true
            if let thinking = event.content_block?.thinking, !thinking.isEmpty {
                actions.append(.delta(thinking, marksPrimaryOutput: false))
            }
        } else if blockType == "text" {
            closeThinkingIfNeeded(state: &state, actions: &actions)
            if let text = event.content_block?.text, !text.isEmpty {
                actions.append(.delta(text, marksPrimaryOutput: true))
            }
        }
    }

    private func reduceContentBlockDelta(
        _ event: AnthropicStreamEvent,
        state: inout AnthropicStreamEventState,
        actions: inout [AnthropicStreamAction]
    ) {
        let deltaType = (event.delta?.type ?? "").lowercased()
        if deltaType.contains("thinking") {
            openThinkingIfNeeded(state: &state, actions: &actions)
            state.thinkingActive = true
            let thinking = event.delta?.thinking ?? event.delta?.text ?? ""
            if !thinking.isEmpty {
                actions.append(.delta(thinking, marksPrimaryOutput: false))
            }
        } else {
            closeThinkingIfNeeded(state: &state, actions: &actions)
            if let text = event.delta?.text, !text.isEmpty {
                actions.append(.delta(text, marksPrimaryOutput: true))
            }
        }
    }

    private func openThinkingIfNeeded(
        state: inout AnthropicStreamEventState,
        actions: inout [AnthropicStreamAction]
    ) {
        guard !state.sentThinkOpen else { return }
        actions.append(.delta(thinkOpenLine, marksPrimaryOutput: false))
        state.sentThinkOpen = true
    }

    private func closeThinkingIfNeeded(
        state: inout AnthropicStreamEventState,
        actions: inout [AnthropicStreamAction]
    ) {
        guard state.thinkingActive, state.sentThinkOpen, !state.sentThinkClose else { return }
        actions.append(.delta(thinkCloseLine, marksPrimaryOutput: false))
        state.sentThinkClose = true
        state.thinkingActive = false
    }
}
