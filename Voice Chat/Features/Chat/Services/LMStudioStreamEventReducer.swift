//
//  LMStudioStreamEventReducer.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct LMStudioStreamEventState: Equatable {
    var isLegacyThinkStream = false
    var sawAnyPrimaryAssistantToken = false
    var sawAnyReasoningToken = false
    var newFormatActive = false
    var sentThinkOpen = false
    var sentThinkClose = false
    var pendingStreamErrorMessage: String?
}

enum LMStudioStreamAction: Equatable {
    case delta(String, marksPrimaryOutput: Bool)
    case metadata(ChatResponseMetadata)
    case finish
    case fail(String)
    case retryableFailure(String, statusCode: Int)
}

struct LMStudioStreamEventReducer {
    private let metadataExtractor: ChatResponseMetadataExtracting
    private let thinkOpenLine = "<think>\n"
    private let thinkCloseLine = "\n</think>\n"

    init(metadataExtractor: ChatResponseMetadataExtracting = ChatResponseMetadataExtractor()) {
        self.metadataExtractor = metadataExtractor
    }

    func reduce(
        _ event: LMStudioChatStreamEvent,
        fallbackType: String?,
        state: inout LMStudioStreamEventState
    ) -> [LMStudioStreamAction] {
        let resolvedType = event.type ?? fallbackType
        guard let rawType = resolvedType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty else {
            return []
        }

        var actions: [LMStudioStreamAction] = []
        let metadata = metadata(from: event)
        if metadata.hasAnyValue {
            actions.append(.metadata(metadata))
        }

        switch rawType.lowercased() {
        case "reasoning.start":
            state.newFormatActive = true
            openThinkIfNeeded(state: &state, actions: &actions)

        case "reasoning.delta":
            state.newFormatActive = true
            openThinkIfNeeded(state: &state, actions: &actions)
            if let content = event.content, !content.isEmpty {
                state.sawAnyReasoningToken = true
                actions.append(.delta(content, marksPrimaryOutput: false))
            }

        case "reasoning.end":
            break

        case "tool_call.start", "tool_call.arguments", "tool_call.success":
            break

        case "tool_call.failure":
            let message = toolFailureMessage(from: event)
            if !message.isEmpty {
                state.pendingStreamErrorMessage = message
            }

        case "message", "message.delta", "response.output_text.delta", "response.content":
            closeThinkIfNeeded(state: &state, actions: &actions)
            if let chunk = primaryDeltaChunk(from: event) {
                state.sawAnyPrimaryAssistantToken = true
                actions.append(.delta(chunk, marksPrimaryOutput: true))
            }

        case "chat.end", "response.completed":
            if !state.sawAnyReasoningToken {
                let reasoningText = completedReasoningText(from: event)
                if !reasoningText.isEmpty {
                    state.newFormatActive = true
                    openThinkIfNeeded(state: &state, actions: &actions)
                    state.sawAnyReasoningToken = true
                    actions.append(.delta(reasoningText, marksPrimaryOutput: false))
                }
            }
            closeThinkIfNeeded(state: &state, actions: &actions)
            if !state.sawAnyPrimaryAssistantToken {
                let fullText = completedFullText(from: event)
                if !fullText.isEmpty {
                    state.sawAnyPrimaryAssistantToken = true
                    actions.append(.delta(fullText, marksPrimaryOutput: true))
                }
            }
            if !state.sawAnyPrimaryAssistantToken {
                if let pending = state.pendingStreamErrorMessage?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !pending.isEmpty {
                    actions.append(.fail(pending))
                    return actions
                }
                if state.sawAnyReasoningToken {
                    actions.append(.finish)
                }
                return actions
            }
            actions.append(.finish)

        case "chat.error", "error":
            let message = event.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedMessage = message.flatMap { $0.isEmpty ? nil : $0 }
                ?? NSLocalizedString("LM Studio stream error.", comment: "Fallback error shown for an LM Studio error event")
            if let statusCode = event.error?.retryableStatusCode {
                actions.append(.retryableFailure(resolvedMessage, statusCode: statusCode))
            } else {
                actions.append(.fail(resolvedMessage))
            }

        case "chat.start",
             "model_load.start", "model_load.progress", "model_load.end",
             "prompt_processing.start", "prompt_processing.progress", "prompt_processing.end",
             "message.start", "message.end":
            break

        default:
            break
        }

        return actions
    }

    private func metadata(from event: LMStudioChatStreamEvent) -> ChatResponseMetadata {
        var metadata = ChatResponseMetadata.empty
        if let responseID = event.response_id ?? event.result?.response_id ?? event.response?.response_id,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.providerResponseID = responseID
        }
        if let stats = event.stats ?? event.result?.stats ?? event.response?.stats {
            metadata.outputTokenCount = metadataExtractor.normalizedTokenCount(stats.total_output_tokens)
            metadata.reasoningOutputTokenCount = metadataExtractor.normalizedTokenCount(stats.reasoning_output_tokens)
            metadata.tokensPerSecond = stats.tokens_per_second
            metadata.timeToFirstTokenSeconds = stats.time_to_first_token_seconds
        }
        return metadata
    }

    private func primaryDeltaChunk(from event: LMStudioChatStreamEvent) -> String? {
        [
            event.content,
            event.delta,
            event.text,
            event.output_text,
            event.response?.output_text,
            event.response?.text,
            event.response?.content
        ]
            .compactMap { $0 }
            // Preserve whitespace-only deltas (for example a standalone " " token),
            // otherwise streamed output can lose spacing between words.
            .first(where: { !$0.isEmpty })
    }

    private func completedFullText(from event: LMStudioChatStreamEvent) -> String {
        [
            event.result?.primaryMessageText,
            event.response?.primaryMessageText,
            event.output_text,
            event.content,
            event.text,
            event.delta
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private func completedReasoningText(from event: LMStudioChatStreamEvent) -> String {
        [
            event.result?.reasoningText,
            event.response?.reasoningText
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private func toolFailureMessage(from event: LMStudioChatStreamEvent) -> String {
        if let reason = event.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            return reason
        }
        let toolName = event.metadata?.tool_name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let toolName, !toolName.isEmpty {
            return String.localizedStringWithFormat(
                NSLocalizedString("Tool call failed: %@", comment: "LM Studio tool-call failure with tool name"),
                toolName
            )
        }
        return NSLocalizedString(
            "Tool call failed.",
            comment: "Fallback error shown when LM Studio reports a tool-call failure without details"
        )
    }

    private func openThinkIfNeeded(
        state: inout LMStudioStreamEventState,
        actions: inout [LMStudioStreamAction]
    ) {
        guard !state.isLegacyThinkStream, !state.sentThinkOpen else { return }
        actions.append(.delta(thinkOpenLine, marksPrimaryOutput: false))
        state.sentThinkOpen = true
    }

    private func closeThinkIfNeeded(
        state: inout LMStudioStreamEventState,
        actions: inout [LMStudioStreamAction]
    ) {
        guard state.newFormatActive,
              !state.isLegacyThinkStream,
              state.sentThinkOpen,
              !state.sentThinkClose else {
            return
        }
        actions.append(.delta(thinkCloseLine, marksPrimaryOutput: false))
        state.sentThinkClose = true
    }
}
