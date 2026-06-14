//
//  OpenAICompatibleStreamEventReducer.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct OpenAICompatibleStreamEventState: Equatable {
    var isLegacyThinkStream = false
    var sawAnyAssistantToken = false
    var sawAnyPrimaryAssistantToken = false
    var newFormatActive = false
    var sentThinkOpen = false
    var sentThinkClose = false
    var lastProcessedSSESequenceNumber: Int?
    var reasoningDeltaItemIDs = Set<String>()
    var outputTextDeltaItemIDs = Set<String>()
}

enum OpenAICompatibleStreamAction: Equatable {
    case delta(String, marksPrimaryOutput: Bool)
    case metadata(ChatResponseMetadata)
    case finish
    case fail(String)
}

struct OpenAICompatibleStreamReduction: Equatable {
    var handled: Bool
    var actions: [OpenAICompatibleStreamAction] = []
}

struct OpenAICompatibleStreamEventReducer {
    private let metadataExtractor: ChatResponseMetadataExtracting
    private let textExtractor: ChatResponseTextExtracting
    private let payloadExtractor: ChatStreamPayloadExtracting
    private let thinkOpenLine = "<think>\n"
    private let thinkCloseLine = "\n</think>\n"

    init(
        metadataExtractor: ChatResponseMetadataExtracting = ChatResponseMetadataExtractor(),
        textExtractor: ChatResponseTextExtracting = ChatResponseTextExtractor(),
        payloadExtractor: ChatStreamPayloadExtracting = ChatStreamPayloadExtractor()
    ) {
        self.metadataExtractor = metadataExtractor
        self.textExtractor = textExtractor
        self.payloadExtractor = payloadExtractor
    }

    func reduce(
        jsonData: Data,
        fallbackType: String?,
        state: inout OpenAICompatibleStreamEventState
    ) -> OpenAICompatibleStreamReduction {
        if let decoded = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData),
           decoded.choices != nil || decoded.usage != nil || decoded.id != nil || decoded.timings != nil {
            return reduce(decodedChunk: decoded, state: &state)
        }

        guard let object = try? JSONSerialization.jsonObject(with: jsonData, options: []),
              let dictionary = object as? [String: Any] else {
            return OpenAICompatibleStreamReduction(handled: false)
        }

        if let sequenceNumber = payloadExtractor.sseSequenceNumber(from: dictionary) {
            if let lastProcessed = state.lastProcessedSSESequenceNumber,
               sequenceNumber <= lastProcessed {
                return OpenAICompatibleStreamReduction(handled: true)
            }
            state.lastProcessedSSESequenceNumber = sequenceNumber
        }

        if let streamError = payloadExtractor.sseStreamErrorMessage(from: dictionary) {
            return OpenAICompatibleStreamReduction(handled: true, actions: [.fail(streamError)])
        }

        var actions: [OpenAICompatibleStreamAction] = []
        let metadata = metadataExtractor.extractResponseMetadata(from: dictionary, style: .openAIChatCompletions)
        if metadata.hasAnyValue {
            actions.append(.metadata(metadata))
        }

        let rawType = (dictionary["type"] as? String) ?? fallbackType ?? ""
        let eventType = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if eventType.isEmpty {
            if let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                appendDelta(chunk, to: &actions, state: &state)
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
            return OpenAICompatibleStreamReduction(handled: metadata.hasAnyValue, actions: actions)
        }

        switch eventType {
        case "response.created", "response.in_progress", "response.output_item.added", "response.content_part.added":
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.reasoning_text.delta":
            state.newFormatActive = true
            openThinkIfNeeded(actions: &actions, state: &state)
            if let itemID = payloadExtractor.sseItemID(from: dictionary) {
                state.reasoningDeltaItemIDs.insert(itemID)
            }
            if let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                appendDelta(chunk, marksPrimaryOutput: false, to: &actions, state: &state)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.reasoning_text.done":
            state.newFormatActive = true
            openThinkIfNeeded(actions: &actions, state: &state)
            let itemID = payloadExtractor.sseItemID(from: dictionary)
            let sawReasoningDeltaForItem: Bool
            if let itemID {
                sawReasoningDeltaForItem = state.reasoningDeltaItemIDs.contains(itemID)
            } else {
                sawReasoningDeltaForItem = !state.reasoningDeltaItemIDs.isEmpty
            }
            if !sawReasoningDeltaForItem,
               let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary),
               !chunk.isEmpty {
                appendDelta(chunk, marksPrimaryOutput: false, to: &actions, state: &state)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_text.delta", "response.content_part.delta", "response.delta", "message.delta":
            closeThinkIfNeeded(actions: &actions, state: &state)
            if let itemID = payloadExtractor.sseItemID(from: dictionary) {
                state.outputTextDeltaItemIDs.insert(itemID)
            }
            if let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                appendDelta(chunk, to: &actions, state: &state)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_text.done", "response.content_part.done":
            if eventType == "response.content_part.done",
               let partType = payloadExtractor.ssePartType(from: dictionary),
               partType.contains("reasoning") {
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
            closeThinkIfNeeded(actions: &actions, state: &state)
            let itemID = payloadExtractor.sseItemID(from: dictionary)
            let sawOutputDeltaForItem: Bool
            if let itemID {
                sawOutputDeltaForItem = state.outputTextDeltaItemIDs.contains(itemID)
            } else {
                sawOutputDeltaForItem = false
            }
            if !sawOutputDeltaForItem,
               !state.sawAnyPrimaryAssistantToken,
               let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary),
               !chunk.isEmpty {
                appendDelta(chunk, to: &actions, state: &state)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_item.done":
            if let itemType = payloadExtractor.sseItemType(from: dictionary),
               itemType.contains("reasoning") || itemType.contains("tool") {
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
            closeThinkIfNeeded(actions: &actions, state: &state)
            if !state.sawAnyPrimaryAssistantToken {
                if let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary),
                   !chunk.isEmpty {
                    appendDelta(chunk, to: &actions, state: &state)
                } else if let recovered = textExtractor.extractOpenAIAssistantText(from: dictionary),
                          !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appendDelta(recovered, to: &actions, state: &state)
                }
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.completed", "response.done":
            closeThinkIfNeeded(actions: &actions, state: &state)
            if !state.sawAnyPrimaryAssistantToken {
                if let response = dictionary["response"] as? [String: Any],
                   let recovered = textExtractor.extractOpenAIAssistantText(from: response),
                   !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appendDelta(recovered, to: &actions, state: &state)
                } else if let recovered = textExtractor.extractOpenAIAssistantText(from: dictionary),
                          !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appendDelta(recovered, to: &actions, state: &state)
                }
            }
            if state.sawAnyPrimaryAssistantToken || state.sawAnyAssistantToken {
                actions.append(.finish)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.failed", "error":
            let message = payloadExtractor.openAICompatibleStreamErrorMessage(from: dictionary) ?? NSLocalizedString(
                "OpenAI Compatible API error",
                comment: "Fallback error shown when OpenAI-compatible stream returns an error event without a message"
            )
            actions.append(.fail(message))
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        default:
            if let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                if eventType.contains("reasoning") {
                    state.newFormatActive = true
                    openThinkIfNeeded(actions: &actions, state: &state)
                    appendDelta(chunk, marksPrimaryOutput: false, to: &actions, state: &state)
                } else {
                    closeThinkIfNeeded(actions: &actions, state: &state)
                    appendDelta(chunk, to: &actions, state: &state)
                }
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
            if !state.sawAnyPrimaryAssistantToken,
               let recovered = textExtractor.extractOpenAIAssistantText(from: dictionary),
               !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                closeThinkIfNeeded(actions: &actions, state: &state)
                appendDelta(recovered, to: &actions, state: &state)
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
            return OpenAICompatibleStreamReduction(handled: metadata.hasAnyValue, actions: actions)
        }
    }

    private func reduce(
        decodedChunk chunk: ChatCompletionChunk,
        state: inout OpenAICompatibleStreamEventState
    ) -> OpenAICompatibleStreamReduction {
        var actions: [OpenAICompatibleStreamAction] = []
        var metadata = ChatResponseMetadata.empty
        if let responseID = chunk.id,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.providerResponseID = responseID
        }
        if let usage = chunk.usage {
            metadata.outputTokenCount = usage.completion_tokens
            metadata.reasoningOutputTokenCount = usage.completion_tokens_details?.reasoning_tokens
        }
        if let timings = chunk.timings {
            if metadata.outputTokenCount == nil, let predictedN = timings.predicted_n {
                metadata.outputTokenCount = predictedN
            }
            if metadata.tokensPerSecond == nil, let predictedPerSecond = timings.predicted_per_second {
                metadata.tokensPerSecond = predictedPerSecond
            }
        }

        for choice in chunk.choices ?? [] {
            if metadata.finishReason == nil,
               let finishReason = choice.finish_reason,
               !finishReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = finishReason
            }
            guard let delta = choice.delta else { continue }

            let deltaText = delta.content ?? ""

            if deltaText.contains("<think>") || deltaText.contains("</think>") {
                state.isLegacyThinkStream = true
            }

            var reasoningText = delta.reasoning?.text ?? ""
            if reasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reasoningText = delta.reasoning_content ?? ""
            }
            if !reasoningText.isEmpty {
                state.newFormatActive = true
                openThinkIfNeeded(actions: &actions, state: &state)
                appendDelta(reasoningText, marksPrimaryOutput: false, to: &actions, state: &state)
            }

            if !deltaText.isEmpty {
                closeThinkIfNeeded(actions: &actions, state: &state)
                appendDelta(deltaText, to: &actions, state: &state)
            }
        }

        if metadata.hasAnyValue {
            actions.append(.metadata(metadata))
        }
        return OpenAICompatibleStreamReduction(handled: true, actions: actions)
    }

    private func openThinkIfNeeded(
        actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        guard !state.isLegacyThinkStream, !state.sentThinkOpen else { return }
        appendDelta(thinkOpenLine, marksPrimaryOutput: false, to: &actions, state: &state)
        state.sentThinkOpen = true
    }

    private func closeThinkIfNeeded(
        actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        guard state.newFormatActive,
              !state.isLegacyThinkStream,
              state.sentThinkOpen,
              !state.sentThinkClose else {
            return
        }
        appendDelta(thinkCloseLine, marksPrimaryOutput: false, to: &actions, state: &state)
        state.sentThinkClose = true
    }

    private func appendDelta(
        _ piece: String,
        marksPrimaryOutput: Bool = true,
        to actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        actions.append(.delta(piece, marksPrimaryOutput: marksPrimaryOutput))
        state.sawAnyAssistantToken = true
        if marksPrimaryOutput {
            state.sawAnyPrimaryAssistantToken = true
        }
    }
}
