//
//  LMStudioStreamingModels.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

/// LM Studio REST API stream event model (`/api/v1/chat`).
struct LMStudioChatStreamEvent: Decodable {
    let type: String?
    let content: String?
    let delta: String?
    let text: String?
    let output_text: String?
    let stats: LMStudioChatStreamStats?
    let response_id: String?
    let error: LMStudioChatStreamErrorPayload?
    let result: LMStudioChatStreamResult?
    let response: LMStudioChatStreamCompletedResponse?

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case delta
        case text
        case output_text
        case stats
        case response_id
        case error
        case result
        case response
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = Self.decodeLooseText(from: container, forKey: .type)
        content = Self.decodeLooseText(from: container, forKey: .content)
        delta = Self.decodeLooseText(from: container, forKey: .delta)
        text = Self.decodeLooseText(from: container, forKey: .text)
        output_text = Self.decodeLooseText(from: container, forKey: .output_text)
        response_id = Self.decodeLooseText(from: container, forKey: .response_id)

        stats = try? container.decodeIfPresent(LMStudioChatStreamStats.self, forKey: .stats)
        error = try? container.decodeIfPresent(LMStudioChatStreamErrorPayload.self, forKey: .error)
        result = try? container.decodeIfPresent(LMStudioChatStreamResult.self, forKey: .result)
        response = try? container.decodeIfPresent(LMStudioChatStreamCompletedResponse.self, forKey: .response)
    }

    private static func decodeLooseText(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let direct = try? container.decodeIfPresent(String.self, forKey: key) {
            return direct
        }
        if let fallback = try? container.decodeIfPresent(AnyDecodable.self, forKey: key) {
            let flattened = flattenLooseValue(fallback.value)
            return flattened.isEmpty ? nil : flattened
        }
        return nil
    }

    private static func flattenLooseValue(_ value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let object = value as? [String: AnyDecodable] {
            for key in ["content", "text", "delta", "output_text", "message", "value"] {
                if let candidate = object[key] {
                    let flattened = flattenLooseValue(candidate.value)
                    if !flattened.isEmpty {
                        return flattened
                    }
                }
            }
            return object.keys.sorted().compactMap { key in
                object[key].map { flattenLooseValue($0.value) }
            }.joined()
        }
        if let array = value as? [Any] {
            return array.map(flattenLooseValue).joined()
        }
        return ""
    }
}

struct LMStudioChatStreamErrorPayload: Decodable {
    let message: String?
}

struct LMStudioChatStreamResult: Decodable {
    let output: [LMStudioChatStreamOutputItem]?
    let stats: LMStudioChatStreamStats?
    let response_id: String?
    let model_instance_id: String?

    var primaryMessageText: String {
        guard let output else { return "" }
        for item in output {
            let normalizedType = item.type?.lowercased()
            if normalizedType == "reasoning" || normalizedType == "tool_call" || normalizedType == "invalid_tool_call" {
                continue
            }
            let text = item.contentText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return ""
    }
}

struct LMStudioChatStreamCompletedResponse: Decodable {
    let output: [LMStudioChatStreamOutputItem]?
    let output_text: String?
    let content: String?
    let text: String?
    let stats: LMStudioChatStreamStats?
    let response_id: String?

    var primaryMessageText: String {
        if let output_text, !output_text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return output_text
        }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }
        guard let output else { return "" }
        for item in output {
            let normalizedType = item.type?.lowercased()
            if normalizedType == "reasoning" || normalizedType == "tool_call" || normalizedType == "invalid_tool_call" {
                continue
            }
            let text = item.contentText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return ""
    }
}

struct LMStudioChatStreamStats: Decodable {
    let total_output_tokens: Double?
    let reasoning_output_tokens: Double?
    let tokens_per_second: Double?
    let time_to_first_token_seconds: Double?
}

struct LMStudioChatStreamOutputItem: Decodable {
    let type: String?
    let contentText: String

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case text
        case value
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)

        if let directText = try? container.decode(String.self, forKey: .content) {
            contentText = directText
            return
        }
        if let singlePart = try? container.decode(LMStudioChatStreamOutputContent.self, forKey: .content),
           let text = singlePart.primaryText {
            contentText = text
            return
        }
        if let parts = try? container.decode([LMStudioChatStreamOutputContent].self, forKey: .content) {
            contentText = parts.compactMap(\.primaryText).joined()
            return
        }
        if let fallback = try? container.decode(AnyDecodable.self, forKey: .content) {
            contentText = LMStudioChatStreamOutputItem.flattenUnknownContent(fallback.value)
            return
        }
        if let directText = try? container.decode(String.self, forKey: .text) {
            contentText = directText
            return
        }
        if let directValue = try? container.decode(String.self, forKey: .value) {
            contentText = directValue
            return
        }
        if let fallback = try? container.decode(AnyDecodable.self, forKey: .message) {
            contentText = LMStudioChatStreamOutputItem.flattenUnknownContent(fallback.value)
            return
        }

        contentText = ""
    }

    private static func flattenUnknownContent(_ value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let object = value as? [String: AnyDecodable] {
            if let text = object["text"]?.stringValue, !text.isEmpty {
                return text
            }
            if let text = object["content"]?.stringValue, !text.isEmpty {
                return text
            }
            return object.values.map { flattenUnknownContent($0.value) }.joined()
        }
        if let array = value as? [Any] {
            return array.map(flattenUnknownContent).joined()
        }
        return ""
    }
}

struct LMStudioChatStreamOutputContent: Decodable {
    let type: String?
    let text: String?
    let content: String?
    let value: String?

    var primaryText: String? {
        for candidate in [text, content, value] {
            guard let candidate else { continue }
            if !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }
}
