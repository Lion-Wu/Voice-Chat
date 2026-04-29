//
//  ChatModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Streaming Chunk Models

struct ChatCompletionChunk: Decodable {
    var id: String?
    var object: String?
    var created: Int?
    var model: String?
    var choices: [Choice]?
    var usage: ChatCompletionUsage?
    var timings: LlamaServerTimings?
}

struct Choice: Decodable {
    var index: Int?
    var finish_reason: String?
    var delta: Delta?
}

struct ChatResponseMetadata: Sendable {
    var providerResponseID: String?
    var outputTokenCount: Int?
    var reasoningOutputTokenCount: Int?
    var tokensPerSecond: Double?
    var timeToFirstTokenSeconds: Double?
    var finishReason: String?

    static let empty = ChatResponseMetadata()

    var hasAnyValue: Bool {
        providerResponseID != nil ||
        outputTokenCount != nil ||
        reasoningOutputTokenCount != nil ||
        tokensPerSecond != nil ||
        timeToFirstTokenSeconds != nil ||
        finishReason != nil
    }

    mutating func merge(_ update: ChatResponseMetadata) {
        if let providerResponseID = update.providerResponseID,
           !providerResponseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.providerResponseID = providerResponseID
        }
        if let outputTokenCount = update.outputTokenCount {
            self.outputTokenCount = outputTokenCount
        }
        if let reasoningOutputTokenCount = update.reasoningOutputTokenCount {
            self.reasoningOutputTokenCount = reasoningOutputTokenCount
        }
        if let tokensPerSecond = update.tokensPerSecond, tokensPerSecond.isFinite, tokensPerSecond >= 0 {
            self.tokensPerSecond = tokensPerSecond
        }
        if let timeToFirstTokenSeconds = update.timeToFirstTokenSeconds,
           timeToFirstTokenSeconds.isFinite,
           timeToFirstTokenSeconds >= 0 {
            self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
        }
        if let finishReason = update.finishReason,
           !finishReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.finishReason = finishReason
        }
    }
}

struct ChatCompletionUsage: Decodable {
    var completion_tokens: Int?
    var total_tokens: Int?
    var completion_tokens_details: ChatCompletionUsageDetails?
}

struct ChatCompletionUsageDetails: Decodable {
    var reasoning_tokens: Int?
}

struct LlamaServerTimings: Decodable {
    var cache_n: Int?
    var prompt_n: Int?
    var predicted_n: Int?
    var predicted_per_second: Double?
}

/// Decodes reasoning fields produced by LM Studio v0.3.23 and later.
struct ReasoningValue: Codable {
    let text: String

    init(from decoder: Decoder) throws {
        if let single = try? String(from: decoder) {
            self.text = single
            return
        }
        if let obj = try? AnyDict(from: decoder) {
            if let s = obj.dict["content"]?.stringValue ?? obj.dict["text"]?.stringValue {
                self.text = s
                return
            }
            let joined = obj.dict.values.compactMap { $0.stringValue }.joined()
            if !joined.isEmpty {
                self.text = joined
                return
            }
        }
        if let arr = try? [AnyDict](from: decoder) {
            let collected = arr.compactMap { item in
                item.dict["content"]?.stringValue ?? item.dict["text"]?.stringValue
            }.joined()
            self.text = collected
            return
        }
        self.text = ""
    }
}

struct AnyDecodable: Decodable {
    let value: Any

    var stringValue: String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            value = s
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let obj = try? AnyDict(from: decoder) {
            value = obj.dict
        } else if let arr = try? [AnyDecodable](from: decoder) {
            value = arr.map { $0.value }
        } else {
            value = NSNull()
        }
    }
}

fileprivate struct DynamicCodingKey: CodingKey {
    let stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
}

struct AnyDict: Decodable {
    let dict: [String: AnyDecodable]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var result: [String: AnyDecodable] = [:]
        for key in container.allKeys {
            result[key.stringValue] = try container.decode(AnyDecodable.self, forKey: key)
        }
        self.dict = result
    }
}

struct Delta: Decodable {
    var role: String?
    var content: String?
    var reasoning: ReasoningValue?
    var reasoning_content: String?

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoning
        case reasoning_content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try? container.decodeIfPresent(String.self, forKey: .role)
        reasoning = try? container.decodeIfPresent(ReasoningValue.self, forKey: .reasoning)
        reasoning_content = try? container.decodeIfPresent(String.self, forKey: .reasoning_content)

        if let text = try? container.decodeIfPresent(String.self, forKey: .content) {
            content = text
            return
        }
        if let loose = try? container.decodeIfPresent(AnyDecodable.self, forKey: .content) {
            let flattened = Self.flattenedContentText(from: loose.value)
            content = flattened.isEmpty ? nil : flattened
            return
        }
        content = nil
    }

    private static func flattenedContentText(from value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let object = value as? [String: AnyDecodable] {
            for key in ["text", "content", "value", "delta"] {
                if let candidate = object[key] {
                    let flattened = flattenedContentText(from: candidate.value)
                    if !flattened.isEmpty {
                        return flattened
                    }
                }
            }
            return object.values.map { flattenedContentText(from: $0.value) }.joined()
        }
        if let array = value as? [Any] {
            return array.map(flattenedContentText(from:)).joined()
        }
        return ""
    }
}

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

/// Anthropic SSE event model (`/v1/messages`).
struct AnthropicStreamEvent: Decodable {
    let type: String?
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
    let stop_reason: String?
}

struct AnthropicStreamContentBlock: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
}

struct AnthropicStreamErrorPayload: Decodable {
    let type: String?
    let message: String?
}

struct AnthropicStreamUsage: Decodable {
    let output_tokens: Int?
}

struct AnthropicStreamMessage: Decodable {
    let id: String?
    let stop_reason: String?
    let usage: AnthropicStreamUsage?
}

enum ChatNetworkError: Error {
    case invalidURL
    case serverError(statusCode: Int?, message: String)
    case timeout(String)
    case emptyResponse
}

extension ChatNetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid API URL", comment: "Shown when the configured chat API URL is invalid")
        case .serverError(_, let message):
            return message
        case .timeout(let message):
            return message
        case .emptyResponse:
            return NSLocalizedString(
                "Server returned an empty response",
                comment: "Shown when the request completes without any assistant output"
            )
        }
    }
}
