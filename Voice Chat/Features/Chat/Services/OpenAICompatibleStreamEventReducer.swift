//
//  OpenAICompatibleStreamEventReducer.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct OpenAICompatibleStreamEventState: Equatable {
    var sawAnyAssistantToken = false
    var sawAnyPrimaryAssistantToken = false
    var isInsideLegacyThinkTag = false
    var shouldTrimNextLegacyThinkLeadingNewline = false
    var legacyThinkTagBuffer = ""
    var lastProcessedSSESequenceNumber: Int?
    var reasoningDeltaItemIDs = Set<String>()
    var outputTextDeltaItemIDs = Set<String>()
}

enum OpenAICompatibleStreamAction: Equatable {
    case delta(String, marksPrimaryOutput: Bool)
    case segment(AssistantStreamSegment, marksPrimaryOutput: Bool)
    case metadata(ChatResponseMetadata)
    case finish
    case incomplete(message: String, segments: [AssistantStreamSegment])
    case fail(String)
    case retryableFailure(String, statusCode: Int)
}

struct OpenAICompatibleStreamReduction: Equatable {
    var handled: Bool
    var actions: [OpenAICompatibleStreamAction] = []
}

struct OpenAICompatibleStreamEventReducer {
    private let metadataExtractor: ChatResponseMetadataExtracting
    private let textExtractor: ChatResponseTextExtracting
    private let payloadExtractor: ChatStreamPayloadExtracting

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
        let dictionary = (try? JSONSerialization.jsonObject(with: jsonData, options: [])) as? [String: Any]
        if let dictionary,
           let streamError = payloadExtractor.sseStreamErrorMessage(from: dictionary) {
            let action: OpenAICompatibleStreamAction
            if let statusCode = ChatStreamErrorRetryClassifier.statusCode(from: dictionary) {
                action = .retryableFailure(streamError, statusCode: statusCode)
            } else {
                action = .fail(streamError)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: [action])
        }

        if let decoded = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData),
           decoded.choices != nil || decoded.usage != nil || decoded.id != nil || decoded.timings != nil {
            return reduce(decodedChunk: decoded, state: &state)
        }

        guard let dictionary else {
            return OpenAICompatibleStreamReduction(handled: false)
        }

        if let sequenceNumber = payloadExtractor.sseSequenceNumber(from: dictionary) {
            if let lastProcessed = state.lastProcessedSSESequenceNumber,
               sequenceNumber <= lastProcessed {
                return OpenAICompatibleStreamReduction(handled: true)
            }
            state.lastProcessedSSESequenceNumber = sequenceNumber
        }

        var actions: [OpenAICompatibleStreamAction] = []
        let metadata = metadataExtractor.extractResponseMetadata(from: dictionary, style: .openAIResponses)
        if metadata.hasAnyValue {
            actions.append(.metadata(metadata))
        }

        let rawType = (dictionary["type"] as? String) ?? fallbackType ?? ""
        let eventType = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if eventType.isEmpty {
            if let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                appendOutputTextDelta(chunk, to: &actions, state: &state)
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
            return OpenAICompatibleStreamReduction(handled: metadata.hasAnyValue, actions: actions)
        }

        switch eventType {
        case "response.created", "response.in_progress":
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_item.added":
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.content_part.added":
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.reasoning.delta", "response.reasoning_text.delta":
            if let itemID = payloadExtractor.sseItemID(from: dictionary) {
                state.reasoningDeltaItemIDs.insert(itemID)
            }
            if let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                appendSegment(.reasoning(id: payloadExtractor.sseItemID(from: dictionary), text: chunk), marksPrimaryOutput: false, to: &actions, state: &state)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.reasoning.done", "response.reasoning_text.done":
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
                appendSegment(.reasoning(id: itemID, text: chunk), marksPrimaryOutput: false, to: &actions, state: &state)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_text.delta", "response.content_part.delta", "response.delta", "message.delta":
            if let itemID = payloadExtractor.sseItemID(from: dictionary) {
                state.outputTextDeltaItemIDs.insert(itemID)
            }
            if let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                appendOutputTextDelta(chunk, to: &actions, state: &state)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.function_call_arguments.delta", "response.function_call_arguments.done":
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_text.done", "response.content_part.done":
            if eventType == "response.content_part.done",
               let partType = payloadExtractor.ssePartType(from: dictionary),
               partType.contains("reasoning") {
                appendCompletedReasoningIfNeeded(from: dictionary, actions: &actions, state: &state)
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
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
                appendOutputTextDelta(chunk, to: &actions, state: &state)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_item.done":
            if let itemType = payloadExtractor.sseItemType(from: dictionary),
               itemType.contains("reasoning") {
                appendCompletedReasoningIfNeeded(from: dictionary, actions: &actions, state: &state)
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
            if let itemType = payloadExtractor.sseItemType(from: dictionary),
               itemType.contains("tool") || itemType == "function_call" {
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
            if !state.sawAnyPrimaryAssistantToken {
                if let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary),
                   !chunk.isEmpty {
                    appendOutputTextDelta(chunk, to: &actions, state: &state)
                } else if let recovered = textExtractor.extractOpenAIAssistantText(from: dictionary),
                          !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appendOutputTextDelta(recovered, to: &actions, state: &state)
                }
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.completed", "response.done":
            flushLegacyThinkTagBufferIfNeeded(actions: &actions, state: &state)
            if !state.sawAnyPrimaryAssistantToken {
                if let response = dictionary["response"] as? [String: Any],
                   let recovered = textExtractor.extractOpenAIAssistantText(from: response),
                   !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appendOutputTextDelta(recovered, to: &actions, state: &state)
                } else if let recovered = textExtractor.extractOpenAIAssistantText(from: dictionary),
                          !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appendOutputTextDelta(recovered, to: &actions, state: &state)
                }
            }
            if state.sawAnyPrimaryAssistantToken || state.sawAnyAssistantToken {
                actions.append(.finish)
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.failed", "error":
            let message = payloadExtractor.openAICompatibleStreamErrorMessage(from: dictionary) ?? NSLocalizedString(
                "OpenAI API error",
                comment: "Fallback error shown when OpenAI-compatible stream returns an error event without a message"
            )
            if let statusCode = ChatStreamErrorRetryClassifier.statusCode(from: dictionary) {
                actions.append(.retryableFailure(message, statusCode: statusCode))
            } else {
                actions.append(.fail(message))
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        default:
            if let chunk = payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                if eventType.contains("reasoning") {
                    appendSegment(.reasoning(id: payloadExtractor.sseItemID(from: dictionary), text: chunk), marksPrimaryOutput: false, to: &actions, state: &state)
                } else {
                    appendOutputTextDelta(chunk, to: &actions, state: &state)
                }
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
            if !state.sawAnyPrimaryAssistantToken,
               let recovered = textExtractor.extractOpenAIAssistantText(from: dictionary),
               !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendOutputTextDelta(recovered, to: &actions, state: &state)
                return OpenAICompatibleStreamReduction(handled: true, actions: actions)
            }
            return OpenAICompatibleStreamReduction(handled: metadata.hasAnyValue, actions: actions)
        }
    }

    func reduceRecoveredOutputText(
        _ text: String,
        state: inout OpenAICompatibleStreamEventState
    ) -> [OpenAICompatibleStreamAction] {
        var actions: [OpenAICompatibleStreamAction] = []
        appendOutputTextDelta(text, to: &actions, state: &state)
        flushLegacyThinkTagBufferIfNeeded(actions: &actions, state: &state)
        if state.sawAnyPrimaryAssistantToken || state.sawAnyAssistantToken {
            actions.append(.finish)
        }
        return actions
    }

    func flushPendingOutput(
        state: inout OpenAICompatibleStreamEventState
    ) -> [OpenAICompatibleStreamAction] {
        var actions: [OpenAICompatibleStreamAction] = []
        flushLegacyThinkTagBufferIfNeeded(actions: &actions, state: &state)
        return actions
    }

    private func appendCompletedReasoningIfNeeded(
        from dictionary: [String: Any],
        actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        let itemID = payloadExtractor.sseItemID(from: dictionary)
        if let itemID, state.reasoningDeltaItemIDs.contains(itemID) {
            return
        }
        if itemID == nil, !state.reasoningDeltaItemIDs.isEmpty {
            return
        }
        guard let text = completedReasoningText(from: dictionary),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        appendSegment(.reasoning(id: itemID, text: text), marksPrimaryOutput: false, to: &actions, state: &state)
        if let itemID {
            state.reasoningDeltaItemIDs.insert(itemID)
        }
    }

    private func completedReasoningText(from dictionary: [String: Any]) -> String? {
        if let part = dictionary["part"] as? [String: Any],
           let text = reasoningText(from: part) {
            return text
        }
        if let item = dictionary["item"] as? [String: Any] {
            if let content = item["content"] as? [[String: Any]],
               let text = reasoningText(from: content) {
                return text
            }
            if let summary = item["summary"] as? [[String: Any]],
               let text = reasoningText(from: summary) {
                return text
            }
        }
        return nil
    }

    private func reasoningText(from part: [String: Any]) -> String? {
        let partType = ((part["type"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard partType == "reasoning_text" || partType == "summary_text" else {
            return nil
        }
        let text = (part["text"] as? String) ?? (part["content"] as? String) ?? ""
        return text.isEmpty ? nil : text
    }

    private func reasoningText(from parts: [[String: Any]]) -> String? {
        let text = parts.compactMap(reasoningText(from:)).joined()
        return text.isEmpty ? nil : text
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

            var reasoningText = delta.reasoning?.text ?? ""
            if reasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reasoningText = delta.reasoning_content ?? ""
            }
            if !reasoningText.isEmpty {
                appendSegment(.reasoning(id: nil, text: reasoningText), marksPrimaryOutput: false, to: &actions, state: &state)
            }

            if !deltaText.isEmpty {
                appendOutputTextDelta(deltaText, to: &actions, state: &state)
            }
        }

        if metadata.hasAnyValue {
            actions.append(.metadata(metadata))
        }
        return OpenAICompatibleStreamReduction(handled: true, actions: actions)
    }

    private func appendOutputTextDelta(
        _ piece: String,
        to actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        guard !piece.isEmpty else { return }
        let text = state.legacyThinkTagBuffer + piece
        state.legacyThinkTagBuffer = ""

        let withheldSuffix = legacyThinkMarkerPrefixSuffix(in: text)
        let parseText: String
        if withheldSuffix.isEmpty {
            parseText = text
        } else {
            parseText = String(text.dropLast(withheldSuffix.count))
            state.legacyThinkTagBuffer = withheldSuffix
        }

        appendLegacyThinkNormalizedText(parseText, to: &actions, state: &state)
    }

    private func flushLegacyThinkTagBufferIfNeeded(
        actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        guard !state.legacyThinkTagBuffer.isEmpty else { return }
        let bufferedText = state.legacyThinkTagBuffer
        state.legacyThinkTagBuffer = ""
        appendLegacyThinkNormalizedText(bufferedText, to: &actions, state: &state)
    }

    private func appendLegacyThinkNormalizedText(
        _ text: String,
        to actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        var remainder = text[...]
        while !remainder.isEmpty {
            if state.isInsideLegacyThinkTag {
                let nextOpen = remainder.range(of: "<think>")
                let nextClose = remainder.range(of: "</think>")
                if let nextOpen,
                   nextClose.map({ nextOpen.lowerBound < $0.lowerBound }) ?? true {
                    appendReasoningText(String(remainder[..<nextOpen.lowerBound]), to: &actions, state: &state)
                    remainder = remainder[nextOpen.upperBound...]
                } else if let nextClose {
                    appendReasoningText(String(remainder[..<nextClose.lowerBound]), to: &actions, state: &state)
                    state.isInsideLegacyThinkTag = false
                    remainder = remainder[nextClose.upperBound...]
                } else {
                    appendReasoningText(String(remainder), to: &actions, state: &state)
                    remainder = remainder[remainder.endIndex...]
                }
            } else if let nextOpen = remainder.range(of: "<think>") {
                appendBodyTextBeforeLegacyThink(String(remainder[..<nextOpen.lowerBound]), to: &actions, state: &state)
                state.isInsideLegacyThinkTag = true
                state.shouldTrimNextLegacyThinkLeadingNewline = true
                remainder = remainder[nextOpen.upperBound...]
            } else if let nextClose = remainder.range(of: "</think>") {
                appendBodyTextBeforeLegacyThink(String(remainder[..<nextClose.lowerBound]), to: &actions, state: &state)
                remainder = remainder[nextClose.upperBound...]
            } else {
                appendBodyText(String(remainder), to: &actions, state: &state)
                remainder = remainder[remainder.endIndex...]
            }
        }
    }

    private func appendReasoningText(
        _ text: String,
        to actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        var text = text
        if state.shouldTrimNextLegacyThinkLeadingNewline {
            text = text.removingOneLeadingNewline()
            if !text.isEmpty {
                state.shouldTrimNextLegacyThinkLeadingNewline = false
            }
        }
        guard !text.isEmpty else { return }
        appendSegment(.reasoning(id: nil, text: text), marksPrimaryOutput: false, to: &actions, state: &state)
    }

    private func appendBodyTextBeforeLegacyThink(
        _ text: String,
        to actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appendBodyText(text, to: &actions, state: &state)
    }

    private func appendBodyText(
        _ text: String,
        to actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        guard !text.isEmpty else { return }
        appendSegment(.text(id: nil, text: text), marksPrimaryOutput: true, to: &actions, state: &state)
    }

    private func legacyThinkMarkerPrefixSuffix(in text: String) -> String {
        let markers = ["<think>", "</think>"]
        let maxPrefixLength = markers.map(\.count).max() ?? 0
        guard !text.isEmpty, maxPrefixLength > 1 else { return "" }
        for length in stride(from: maxPrefixLength - 1, through: 1, by: -1) {
            guard text.count >= length else { continue }
            let suffix = String(text.suffix(length))
            if markers.contains(where: { $0.hasPrefix(suffix) }) {
                return suffix
            }
        }
        return ""
    }

    private func appendSegment(
        _ segment: AssistantStreamSegment,
        marksPrimaryOutput: Bool,
        to actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAICompatibleStreamEventState
    ) {
        actions.append(.segment(segment, marksPrimaryOutput: marksPrimaryOutput))
        state.sawAnyAssistantToken = true
        if marksPrimaryOutput {
            state.sawAnyPrimaryAssistantToken = true
        }
    }
}

private extension String {
    func removingOneLeadingNewline() -> String {
        if hasPrefix("\r\n") {
            return String(dropFirst(2))
        }
        if hasPrefix("\n") || hasPrefix("\r") {
            return String(dropFirst())
        }
        return self
    }
}
