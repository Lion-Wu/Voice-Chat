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

struct ChatResponseMetadata: Sendable, Equatable {
    var providerResponseID: String?
    var requestContext: ChatRequestContextSnapshot?
    var requestUsedPreviousResponseID: Bool?
    var requestPreviousResponseID: String?
    var outputTokenCount: Int?
    var reasoningOutputTokenCount: Int?
    var tokensPerSecond: Double?
    var timeToFirstTokenSeconds: Double?
    var finishReason: String?

    static let empty = ChatResponseMetadata()

    var hasAnyValue: Bool {
        providerResponseID != nil ||
        requestContext != nil ||
        requestUsedPreviousResponseID != nil ||
        requestPreviousResponseID != nil ||
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
        if let requestContext = update.requestContext,
           !requestContext.fingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.requestContext = requestContext
        }
        if let requestUsedPreviousResponseID = update.requestUsedPreviousResponseID {
            self.requestUsedPreviousResponseID = requestUsedPreviousResponseID
            if !requestUsedPreviousResponseID {
                self.requestPreviousResponseID = nil
            }
        }
        if update.requestUsedPreviousResponseID != false,
           let requestPreviousResponseID = update.requestPreviousResponseID,
           !requestPreviousResponseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.requestPreviousResponseID = requestPreviousResponseID
            if update.requestUsedPreviousResponseID == nil {
                self.requestUsedPreviousResponseID = true
            }
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
    var reasoning_details: [JSONValue]?

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoning
        case reasoning_content
        case reasoning_details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try? container.decodeIfPresent(String.self, forKey: .role)
        reasoning = try? container.decodeIfPresent(ReasoningValue.self, forKey: .reasoning)
        reasoning_content = try? container.decodeIfPresent(String.self, forKey: .reasoning_content)
        reasoning_details = try? container.decodeIfPresent([JSONValue].self, forKey: .reasoning_details)

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

enum ChatNetworkError: Error {
    case invalidURL
    case invalidRequestHistory
    case serverError(statusCode: Int?, message: String)
    case timeout(String)
    case emptyResponse
}

struct ChatIncompleteResponseError: LocalizedError, Sendable {
    let message: String
    let segments: [AssistantStreamSegment]
    let metadata: ChatResponseMetadata

    var errorDescription: String? { message }
}

extension ChatNetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid API URL", comment: "Shown when the configured chat API URL is invalid")
        case .invalidRequestHistory:
            return NSLocalizedString(
                "Unable to build a request from the selected conversation branch.",
                comment: "Shown when a chat branch does not end with the intended user message"
            )
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
