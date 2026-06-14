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
                actions.append(.delta(content, marksPrimaryOutput: false))
            }

        case "reasoning.end":
            closeThinkIfNeeded(state: &state, actions: &actions)

        case "message", "message.delta", "response.output_text.delta", "response.content":
            closeThinkIfNeeded(state: &state, actions: &actions)
            if let chunk = primaryDeltaChunk(from: event) {
                state.sawAnyPrimaryAssistantToken = true
                actions.append(.delta(chunk, marksPrimaryOutput: true))
            }

        case "chat.end", "response.completed":
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
                }
                return actions
            }
            actions.append(.finish)

        case "chat.error", "error":
            let message = event.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                state.pendingStreamErrorMessage = message
            }

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
