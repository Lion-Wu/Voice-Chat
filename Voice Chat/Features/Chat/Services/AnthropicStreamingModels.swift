//
//  AnthropicStreamingModels.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

/// Anthropic SSE event model (`/v1/messages`).
struct AnthropicStreamEvent: Decodable {
    let type: String?
    let index: Int?
    let delta: AnthropicStreamDelta?
    let content_block: AnthropicStreamContentBlock?
    let message: AnthropicStreamMessage?
    let usage: AnthropicStreamUsage?
    let error: AnthropicStreamErrorPayload?
}

struct AnthropicStreamDelta: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
    let signature: String?
    let partial_json: String?
    let stop_reason: String?
}

struct AnthropicStreamContentBlock: Decodable {
    let type: String?
    let id: String?
    let name: String?
    let text: String?
    let thinking: String?
    let signature: String?
    let data: String?
    let input: JSONValue?

    var inputJSONString: String? {
        input?.compactJSONString
    }
}

struct AnthropicStreamErrorPayload: Decodable {
    let type: String?
    let message: String?
}

struct AnthropicStreamUsage: Decodable {
    let output_tokens: Int?
    let output_tokens_details: AnthropicStreamUsageDetails?
}

struct AnthropicStreamUsageDetails: Decodable {
    let thinking_tokens: Int?
    let reasoning_tokens: Int?
}

struct AnthropicStreamMessage: Decodable {
    let id: String?
    let stop_reason: String?
    let usage: AnthropicStreamUsage?
}

struct AnthropicAssistantContentAccumulator {
    private struct PartialBlock {
        var type: String
        var id: String?
        var name: String?
        var text: String
        var thinking: String
        var signature: String
        var redactedData: String?
        var input: JSONValue?
        var inputJSON = ""

        var jsonObject: [String: Any]? {
            switch type {
            case "thinking":
                var block: [String: Any] = [
                    "type": "thinking",
                    "thinking": thinking
                ]
                if !signature.isEmpty {
                    block["signature"] = signature
                }
                return block
            case "redacted_thinking":
                guard let redactedData, !redactedData.isEmpty else { return nil }
                return ["type": "redacted_thinking", "data": redactedData]
            case "text":
                return ["type": "text", "text": text]
            case "tool_use":
                guard let id, !id.isEmpty, let name, !name.isEmpty else { return nil }
                return [
                    "type": "tool_use",
                    "id": id,
                    "name": name,
                    "input": decodedInput
                ]
            default:
                return nil
            }
        }

        private var decodedInput: Any {
            let trimmed = inputJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let data = trimmed.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data),
               object is [String: Any] {
                return object
            }
            return input?.jsonObject ?? [:]
        }
    }

    private var blocks: [Int: PartialBlock] = [:]

    var contentBlocks: [[String: Any]] {
        blocks.keys.sorted().compactMap { blocks[$0]?.jsonObject }
    }

    mutating func absorb(_ event: AnthropicStreamEvent) {
        guard let index = event.index,
              let eventType = event.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return
        }

        switch eventType {
        case "content_block_start":
            guard let block = event.content_block else { return }
            blocks[index] = PartialBlock(
                type: (block.type ?? "").lowercased(),
                id: block.id,
                name: block.name,
                text: block.text ?? "",
                thinking: block.thinking ?? "",
                signature: block.signature ?? "",
                redactedData: block.data,
                input: block.input
            )
        case "content_block_delta":
            guard var block = blocks[index] else { return }
            switch event.delta?.type?.lowercased() {
            case "text_delta":
                block.text += event.delta?.text ?? ""
            case "thinking_delta":
                block.thinking += event.delta?.thinking ?? event.delta?.text ?? ""
            case "signature_delta":
                block.signature += event.delta?.signature ?? ""
            case "input_json_delta":
                block.inputJSON += event.delta?.partial_json ?? ""
            default:
                break
            }
            blocks[index] = block
        default:
            break
        }
    }

    mutating func reset() {
        blocks.removeAll(keepingCapacity: true)
    }
}
