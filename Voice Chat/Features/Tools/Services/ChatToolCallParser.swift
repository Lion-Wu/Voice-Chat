//
//  ChatToolCallParser.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

struct ChatToolCallAccumulator: Equatable {
    private var openAIChunks: [String: PartialToolCall] = [:]
    private var anthropicChunks: [String: PartialToolCall] = [:]

    mutating func absorbOpenAICompatiblePayload(_ dictionary: [String: Any], provider: ChatProvider?) -> [ChatToolCallEnvelope] {
        var completed: [ChatToolCallEnvelope] = []
        completed.append(contentsOf: absorbChatCompletionsPayload(dictionary, provider: provider))
        completed.append(contentsOf: absorbResponsesPayload(dictionary, provider: provider))
        return completed
    }

    mutating func absorbAnthropicEvent(_ event: AnthropicStreamEvent, provider: ChatProvider?) -> [ChatToolCallEnvelope] {
        guard let type = event.type?.lowercased() else { return [] }
        switch type {
        case "content_block_start":
            guard let block = event.content_block, block.type == "tool_use" else { return [] }
            let id = block.id ?? UUID().uuidString
            let key = anthropicToolCallKey(for: event) ?? id
            anthropicChunks[key] = PartialToolCall(
                callID: id,
                name: block.name ?? "",
                arguments: initialAnthropicArguments(from: block)
            )
            return []
        case "content_block_delta":
            guard let key = anthropicToolCallKey(for: event) ?? anthropicChunks.keys.sorted().last else { return [] }
            anthropicChunks[key, default: PartialToolCall(callID: key, name: "", arguments: "")]
                .arguments += event.delta?.partial_json ?? ""
            return []
        case "content_block_stop":
            guard let key = anthropicToolCallKey(for: event) ?? anthropicChunks.keys.sorted().last,
                  let partial = anthropicChunks.removeValue(forKey: key),
                  !partial.name.isEmpty else { return [] }
            return [partial.envelope(provider: provider)]
        default:
            return []
        }
    }

    mutating func drain(provider: ChatProvider?) -> [ChatToolCallEnvelope] {
        let openAI = openAIChunks.values.compactMap { partial in
            partial.name.isEmpty ? nil : partial.envelope(provider: provider)
        }
        let anthropic = anthropicChunks.values.map { $0.envelope(provider: provider ?? .anthropic) }
        openAIChunks.removeAll()
        anthropicChunks.removeAll()
        return openAI + anthropic
    }

    private func anthropicToolCallKey(for event: AnthropicStreamEvent) -> String? {
        event.index.map { "index-\($0)" }
    }

    private func initialAnthropicArguments(from block: AnthropicStreamContentBlock) -> String {
        let arguments = block.inputJSONString ?? ""
        return arguments == "{}" ? "" : arguments
    }

    mutating func reset() {
        openAIChunks.removeAll()
        anthropicChunks.removeAll()
    }

    private mutating func absorbChatCompletionsPayload(_ dictionary: [String: Any], provider: ChatProvider?) -> [ChatToolCallEnvelope] {
        guard let choices = dictionary["choices"] as? [[String: Any]] else { return [] }
        var completed: [ChatToolCallEnvelope] = []
        for choice in choices {
            if let delta = choice["delta"] as? [String: Any] {
                absorbChatCompletionsToolContainer(delta)
            }
            if let message = choice["message"] as? [String: Any] {
                absorbChatCompletionsToolContainer(message)
            }

            let finishReason = (choice["finish_reason"] as? String)?.lowercased()
            if isOpenAIToolFinishReason(finishReason) {
                completed.append(contentsOf: openAIChunks.sorted(by: { $0.key < $1.key }).compactMap { _, partial in
                    partial.name.isEmpty ? nil : partial.envelope(provider: provider)
                })
                openAIChunks.removeAll()
            }
        }
        return completed
    }

    private mutating func absorbChatCompletionsToolContainer(_ container: [String: Any]) {
        if let toolCalls = container["tool_calls"] as? [[String: Any]] {
            for item in toolCalls {
                absorbChatCompletionsToolCallItem(item)
            }
        }

        if let functionCall = container["function_call"] as? [String: Any] {
            absorbLegacyFunctionCall(functionCall)
        }
    }

    private mutating func absorbChatCompletionsToolCallItem(_ item: [String: Any]) {
        let key = toolCallKey(from: item)
        var partial = openAIChunks[key] ?? PartialToolCall(callID: key, name: "", arguments: "")
        if let id = item["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            partial.callID = id
        }

        if let function = item["function"] as? [String: Any] {
            if let name = function["name"] as? String {
                partial.name = mergedFunctionName(existing: partial.name, incoming: name)
            } else if let name = item["name"] as? String {
                partial.name = mergedFunctionName(existing: partial.name, incoming: name)
            }

            if let arguments = normalizedArgumentFragment(from: function["arguments"]) {
                partial.arguments += arguments
            }
        } else {
            if let name = item["name"] as? String {
                partial.name = mergedFunctionName(existing: partial.name, incoming: name)
            }
            if let arguments = normalizedArgumentFragment(from: item["arguments"]) {
                partial.arguments += arguments
            }
        }

        openAIChunks[key] = partial
    }

    private mutating func absorbLegacyFunctionCall(_ functionCall: [String: Any]) {
        let key = "legacy-function-call"
        var partial = openAIChunks[key] ?? PartialToolCall(callID: key, name: "", arguments: "")
        if let name = functionCall["name"] as? String {
            partial.name = mergedFunctionName(existing: partial.name, incoming: name)
        }
        if let arguments = normalizedArgumentFragment(from: functionCall["arguments"]) {
            partial.arguments += arguments
        }
        openAIChunks[key] = partial
    }

    private mutating func absorbResponsesPayload(_ dictionary: [String: Any], provider: ChatProvider?) -> [ChatToolCallEnvelope] {
        let eventType = ((dictionary["type"] as? String) ?? "").lowercased()
        var completed: [ChatToolCallEnvelope] = []

        if eventType == "response.output_item.added" || eventType == "response.output_item.done",
           let item = dictionary["item"] as? [String: Any],
           ((item["type"] as? String) ?? "").lowercased() == "function_call" {
            absorbResponsesFunctionCallItem(item, completes: eventType == "response.output_item.done", provider: provider, into: &completed)
        }

        if eventType == "response.function_call_arguments.delta" {
            let itemID = (dictionary["item_id"] as? String) ?? (dictionary["call_id"] as? String) ?? "responses-tool-call"
            openAIChunks[itemID, default: PartialToolCall(callID: dictionary["call_id"] as? String ?? itemID, name: dictionary["name"] as? String ?? "", arguments: "")]
                .arguments += (dictionary["delta"] as? String) ?? ""
        }

        if eventType == "response.function_call_arguments.done" {
            let itemID = (dictionary["item_id"] as? String) ?? (dictionary["call_id"] as? String) ?? "responses-tool-call"
            var partial = openAIChunks[itemID] ?? PartialToolCall(callID: dictionary["call_id"] as? String ?? itemID, name: dictionary["name"] as? String ?? "", arguments: "")
            if let arguments = dictionary["arguments"] as? String { partial.arguments = arguments }
            if let name = dictionary["name"] as? String, !name.isEmpty { partial.name = name }
            if !partial.name.isEmpty {
                completed.append(partial.envelope(provider: provider))
                openAIChunks[itemID] = nil
            } else {
                openAIChunks[itemID] = partial
            }
        }

        if let response = dictionary["response"] as? [String: Any],
           let output = response["output"] as? [[String: Any]] {
            for item in output where ((item["type"] as? String) ?? "").lowercased() == "function_call" {
                absorbResponsesFunctionCallItem(item, completes: true, provider: provider, into: &completed)
            }
        }

        return completed
    }

    private mutating func absorbResponsesFunctionCallItem(
        _ item: [String: Any],
        completes: Bool,
        provider: ChatProvider?,
        into completed: inout [ChatToolCallEnvelope]
    ) {
        let itemID = (item["id"] as? String) ?? (item["call_id"] as? String) ?? UUID().uuidString
        var partial = openAIChunks[itemID] ?? PartialToolCall(callID: item["call_id"] as? String ?? itemID, name: "", arguments: "")
        if let callID = item["call_id"] as? String, !callID.isEmpty { partial.callID = callID }
        if let name = item["name"] as? String, !name.isEmpty { partial.name = name }
        if let arguments = normalizedArgumentFragment(from: item["arguments"]), !arguments.isEmpty {
            partial.arguments = arguments
        }
        if completes, !partial.name.isEmpty {
            completed.append(partial.envelope(provider: provider))
            openAIChunks[itemID] = nil
        } else {
            openAIChunks[itemID] = partial
        }
    }

    private func isOpenAIToolFinishReason(_ finishReason: String?) -> Bool {
        guard let finishReason else { return false }
        return finishReason == "tool_calls" ||
            finishReason == "tool_call" ||
            finishReason == "function_call"
    }

    private func toolCallKey(from item: [String: Any]) -> String {
        if let index = item["index"] as? Int { return "index-\(index)" }
        if let index = item["index"] as? NSNumber { return "index-\(index.intValue)" }
        if let id = item["id"] as? String, !id.isEmpty { return id }
        if openAIChunks.count == 1, let existing = openAIChunks.keys.first {
            return existing
        }
        return UUID().uuidString
    }

    private func mergedFunctionName(existing: String, incoming: String) -> String {
        let incoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return existing }
        guard !existing.isEmpty else { return incoming }
        if incoming == existing { return existing }
        if incoming.hasPrefix(existing) { return incoming }
        if existing.hasSuffix(incoming) { return existing }
        return existing + incoming
    }

    private func normalizedArgumentFragment(from value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            return string
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

private struct PartialToolCall: Equatable {
    var callID: String
    var name: String
    var arguments: String

    func envelope(provider: ChatProvider?) -> ChatToolCallEnvelope {
        ChatToolCallEnvelope(
            callID: callID,
            name: name,
            argumentsJSON: arguments.isEmpty ? "{}" : arguments,
            provider: provider
        )
    }
}
