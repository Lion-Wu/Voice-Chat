//
//  OpenAIResponsesStreamItemReducer.swift
//  Voice Chat
//
//  Created by Codex on 2026/7/2.
//

import Foundation

struct OpenAIResponsesStreamItemState: Equatable {
    var lastProcessedSSESequenceNumber: Int?
    var reasoningDeltaPartKeys = Set<String>()
    var textDeltaPartKeys = Set<String>()
    var sawAnySegment = false
    var sawAnyTextSegment = false
}

struct OpenAIResponsesStreamItemReducer {
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
        state: inout OpenAIResponsesStreamItemState
    ) -> OpenAICompatibleStreamReduction {
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

        var actions: [OpenAICompatibleStreamAction] = []
        let metadata = metadataExtractor.extractResponseMetadata(from: dictionary, style: .openAIResponses)
        if metadata.hasAnyValue {
            actions.append(.metadata(metadata))
        }

        if let streamError = payloadExtractor.sseStreamErrorMessage(from: dictionary) {
            if let statusCode = ChatStreamErrorRetryClassifier.statusCode(from: dictionary) {
                actions.append(.retryableFailure(streamError, statusCode: statusCode))
            } else {
                actions.append(.fail(streamError))
            }
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)
        }

        let rawType = (dictionary["type"] as? String) ?? fallbackType ?? ""
        let eventType = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !eventType.isEmpty else {
            return OpenAICompatibleStreamReduction(handled: metadata.hasAnyValue, actions: actions)
        }

        switch eventType {
        case "response.created", "response.in_progress":
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_item.added":
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.content_part.added", "response.reasoning_summary_part.added":
            appendCompletedPartIfNeeded(from: dictionary, actions: &actions, state: &state)
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.reasoning.delta",
             "response.reasoning_text.delta",
             "response.reasoning_summary_text.delta":
            appendDelta(
                from: dictionary,
                kind: .reasoning,
                text: deltaText(from: dictionary),
                actions: &actions,
                state: &state
            )
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_text.delta", "response.refusal.delta":
            appendDelta(
                from: dictionary,
                kind: .text,
                text: deltaText(from: dictionary),
                actions: &actions,
                state: &state
            )
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.content_part.delta":
            appendDelta(
                from: dictionary,
                kind: isReasoningPart(dictionary) ? .reasoning : .text,
                text: deltaText(from: dictionary),
                actions: &actions,
                state: &state
            )
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.function_call_arguments.delta", "response.function_call_arguments.done":
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_text.done",
             "response.refusal.done",
             "response.reasoning_text.done",
             "response.reasoning_summary_text.done",
             "response.reasoning_summary_part.done",
             "response.content_part.done":
            appendCompletedPartIfNeeded(from: dictionary, actions: &actions, state: &state)
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.output_item.done":
            appendCompletedItemIfNeeded(from: dictionary, actions: &actions, state: &state)
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.completed", "response.done":
            appendRecoveredCompletedResponseIfNeeded(from: dictionary, actions: &actions, state: &state)
            actions.append(.finish)
            return OpenAICompatibleStreamReduction(handled: true, actions: actions)

        case "response.incomplete":
            actions.append(.incomplete(
                message: incompleteResponseMessage(from: dictionary),
                segments: completeResponseSegments(from: dictionary)
            ))
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
            return OpenAICompatibleStreamReduction(handled: metadata.hasAnyValue, actions: actions)
        }
    }

    private enum SegmentKind {
        case reasoning
        case text
    }

    private func incompleteResponseMessage(from dictionary: [String: Any]) -> String {
        let response = dictionary["response"] as? [String: Any]
        let details = (response?["incomplete_details"] as? [String: Any])
            ?? (dictionary["incomplete_details"] as? [String: Any])
        let reason = (details?["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !reason.isEmpty {
            return String(
                format: NSLocalizedString("Response was incomplete: %@", comment: "OpenAI Responses incomplete response reason"),
                reason
            )
        }
        return NSLocalizedString("Response was incomplete.", comment: "OpenAI Responses incomplete response error")
    }

    private func appendDelta(
        from dictionary: [String: Any],
        kind: SegmentKind,
        text: String?,
        actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAIResponsesStreamItemState
    ) {
        guard let text, !text.isEmpty else { return }
        let itemID = itemID(from: dictionary)
        let keys = partKeys(from: dictionary, kind: kind)
        switch kind {
        case .reasoning:
            actions.append(.segment(.reasoning(id: itemID, text: text), marksPrimaryOutput: false))
            state.reasoningDeltaPartKeys.formUnion(keys)
        case .text:
            actions.append(.segment(.text(id: itemID, text: text), marksPrimaryOutput: true))
            state.textDeltaPartKeys.formUnion(keys)
            state.sawAnyTextSegment = true
        }
        state.sawAnySegment = true
    }

    private func appendCompletedPartIfNeeded(
        from dictionary: [String: Any],
        actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAIResponsesStreamItemState
    ) {
        let kind: SegmentKind = isReasoningPart(dictionary) || isReasoningEvent(dictionary) ? .reasoning : .text
        let keys = partKeys(from: dictionary, kind: kind)
        guard shouldRecover(keys: keys, kind: kind, state: state) else { return }
        let text = kind == .reasoning
            ? completedReasoningText(from: dictionary)
            : completedText(from: dictionary)
        appendRecovered(
            text: text,
            itemID: itemID(from: dictionary),
            keys: keys,
            kind: kind,
            actions: &actions,
            state: &state
        )
    }

    private func appendCompletedItemIfNeeded(
        from dictionary: [String: Any],
        actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAIResponsesStreamItemState
    ) {
        guard let itemType = payloadExtractor.sseItemType(from: dictionary) else { return }
        let itemID = itemID(from: dictionary)
        if itemType == "reasoning" {
            let item = (dictionary["item"] as? [String: Any]) ?? dictionary
            var recoveredPart = false
            for (container, parts) in [("summary", item["summary"]), ("content", item["content"])] {
                guard let parts = parts as? [[String: Any]] else { continue }
                for (index, part) in parts.enumerated() {
                    let keys = partKeys(itemID: itemID, outputIndex: outputIndex(from: dictionary), container: container, index: index)
                    guard shouldRecover(keys: keys, kind: .reasoning, state: state) else { continue }
                    appendRecovered(
                        text: reasoningText(from: part),
                        itemID: itemID,
                        keys: keys,
                        kind: .reasoning,
                        actions: &actions,
                        state: &state
                    )
                    recoveredPart = true
                }
            }
            if !recoveredPart {
                let keys = partKeys(from: dictionary, kind: .reasoning)
                guard shouldRecover(keys: keys, kind: .reasoning, state: state) else { return }
                appendRecovered(
                    text: completedReasoningText(from: dictionary),
                    itemID: itemID,
                    keys: keys,
                    kind: .reasoning,
                    actions: &actions,
                    state: &state
                )
            }
            return
        }

        guard itemType == "message" else { return }
        let item = (dictionary["item"] as? [String: Any]) ?? dictionary
        if let parts = item["content"] as? [[String: Any]] {
            for (index, part) in parts.enumerated() {
                let type = ((part["type"] as? String) ?? "").lowercased()
                guard type == "output_text" || type == "text" || type == "refusal" || type.isEmpty else { continue }
                let keys = partKeys(itemID: itemID, outputIndex: outputIndex(from: dictionary), container: "content", index: index)
                guard shouldRecover(keys: keys, kind: .text, state: state) else { continue }
                appendRecovered(
                    text: text(from: part),
                    itemID: itemID,
                    keys: keys,
                    kind: .text,
                    actions: &actions,
                    state: &state
                )
            }
            return
        }
        let keys = partKeys(from: dictionary, kind: .text)
        guard shouldRecover(keys: keys, kind: .text, state: state) else { return }
        appendRecovered(
            text: completedMessageText(from: dictionary),
            itemID: itemID,
            keys: keys,
            kind: .text,
            actions: &actions,
            state: &state
        )
    }

    private func appendRecoveredCompletedResponseIfNeeded(
        from dictionary: [String: Any],
        actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAIResponsesStreamItemState
    ) {
        let response = (dictionary["response"] as? [String: Any]) ?? dictionary
        if let output = response["output"] as? [[String: Any]] {
            for (index, item) in output.enumerated() {
                let wrapper: [String: Any] = ["item": item, "output_index": index]
                appendCompletedItemIfNeeded(from: wrapper, actions: &actions, state: &state)
            }
            return
        }
        guard !state.sawAnyTextSegment,
              let text = textExtractor.extractOpenAIAssistantText(from: response),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        actions.append(.segment(.text(id: nil, text: text), marksPrimaryOutput: true))
        state.sawAnySegment = true
        state.sawAnyTextSegment = true
    }

    private func completeResponseSegments(from dictionary: [String: Any]) -> [AssistantStreamSegment] {
        var recoveryState = OpenAIResponsesStreamItemState()
        var recoveryActions: [OpenAICompatibleStreamAction] = []
        appendRecoveredCompletedResponseIfNeeded(
            from: dictionary,
            actions: &recoveryActions,
            state: &recoveryState
        )
        return recoveryActions.compactMap { action in
            guard case let .segment(segment, _) = action else { return nil }
            return segment
        }
    }

    private func shouldRecover(
        keys: Set<String>,
        kind: SegmentKind,
        state: OpenAIResponsesStreamItemState
    ) -> Bool {
        switch kind {
        case .reasoning:
            return state.reasoningDeltaPartKeys.isDisjoint(with: keys)
        case .text:
            return state.textDeltaPartKeys.isDisjoint(with: keys)
        }
    }

    private func appendRecovered(
        text: String?,
        itemID: String?,
        keys: Set<String>,
        kind: SegmentKind,
        actions: inout [OpenAICompatibleStreamAction],
        state: inout OpenAIResponsesStreamItemState
    ) {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch kind {
        case .reasoning:
            actions.append(.segment(.reasoning(id: itemID, text: text), marksPrimaryOutput: false))
            state.reasoningDeltaPartKeys.formUnion(keys)
        case .text:
            actions.append(.segment(.text(id: itemID, text: text), marksPrimaryOutput: true))
            state.textDeltaPartKeys.formUnion(keys)
            state.sawAnyTextSegment = true
        }
        state.sawAnySegment = true
    }

    private func itemID(from dictionary: [String: Any]) -> String? {
        if let itemID = payloadExtractor.sseItemID(from: dictionary) {
            return itemID
        }
        if let outputIndex = outputIndex(from: dictionary) {
            return "output_index:\(outputIndex)"
        }
        return nil
    }

    private func partKeys(from dictionary: [String: Any], kind: SegmentKind) -> Set<String> {
        let itemID = itemID(from: dictionary)
        let outputIndex = outputIndex(from: dictionary)
        let eventType = ((dictionary["type"] as? String) ?? "").lowercased()
        if eventType.contains("summary") {
            return partKeys(
                itemID: itemID,
                outputIndex: outputIndex,
                container: "summary",
                index: integer(from: dictionary["summary_index"]) ?? 0
            )
        }
        return partKeys(
            itemID: itemID,
            outputIndex: outputIndex,
            container: kind == .reasoning ? "content" : "content",
            index: integer(from: dictionary["content_index"]) ?? 0
        )
    }

    private func partKeys(
        itemID: String?,
        outputIndex: Int?,
        container: String,
        index: Int
    ) -> Set<String> {
        var keys = Set<String>()
        if let itemID {
            keys.insert("item:\(itemID):\(container):\(index)")
        }
        if let outputIndex {
            keys.insert("output:\(outputIndex):\(container):\(index)")
        }
        if keys.isEmpty {
            keys.insert("unknown_item:\(container):\(index)")
        }
        return keys
    }

    private func integer(from value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func outputIndex(from dictionary: [String: Any]) -> Int? {
        if let number = dictionary["output_index"] as? NSNumber {
            return number.intValue
        }
        if let number = dictionary["output_index"] as? Int {
            return number
        }
        if let raw = dictionary["output_index"] as? String {
            return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func isReasoningPart(_ dictionary: [String: Any]) -> Bool {
        guard let partType = payloadExtractor.ssePartType(from: dictionary) else { return false }
        return partType.contains("reasoning") || partType.contains("summary")
    }

    private func isReasoningEvent(_ dictionary: [String: Any]) -> Bool {
        let type = ((dictionary["type"] as? String) ?? "").lowercased()
        return type.contains("reasoning") || type.contains("summary")
    }

    private func deltaText(from dictionary: [String: Any]) -> String? {
        payloadExtractor.openAICompatibleStreamDeltaText(from: dictionary)
    }

    private func completedMessageText(from dictionary: [String: Any]) -> String? {
        if let item = dictionary["item"] as? [String: Any] {
            return textExtractor.extractOpenAIAssistantText(from: ["item": item])
        }
        return textExtractor.extractOpenAIAssistantText(from: dictionary)
    }

    private func completedText(from dictionary: [String: Any]) -> String? {
        if let part = dictionary["part"] as? [String: Any] {
            return text(from: part)
        }
        if let text = dictionary["text"] as? String, !text.isEmpty {
            return text
        }
        if let refusal = dictionary["refusal"] as? String, !refusal.isEmpty {
            return refusal
        }
        return deltaText(from: dictionary)
    }

    private func text(from part: [String: Any]) -> String? {
        let text = (part["text"] as? String) ??
            (part["refusal"] as? String) ??
            (part["content"] as? String) ?? ""
        return text.isEmpty ? nil : text
    }

    private func completedReasoningText(from dictionary: [String: Any]) -> String? {
        if let text = dictionary["text"] as? String, !text.isEmpty {
            return text
        }
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
}
