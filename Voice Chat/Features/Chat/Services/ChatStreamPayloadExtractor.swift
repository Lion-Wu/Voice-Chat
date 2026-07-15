//
//  ChatStreamPayloadExtractor.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

protocol ChatStreamPayloadExtracting {
    func sseSequenceNumber(from dictionary: [String: Any]) -> Int?
    func sseItemID(from dictionary: [String: Any]) -> String?
    func sseItemType(from dictionary: [String: Any]) -> String?
    func ssePartType(from dictionary: [String: Any]) -> String?
    func openAICompatibleStreamDeltaText(from dictionary: [String: Any]) -> String?
    func openAICompatibleStreamErrorMessage(from dictionary: [String: Any]) -> String?
    func sseStreamErrorMessage(from dictionary: [String: Any]) -> String?
    func sseStreamErrorMessage(from rawBodyData: Data) -> String?
}

struct ChatStreamPayloadExtractor: ChatStreamPayloadExtracting {
    private let textExtractor: ChatResponseTextExtracting

    init(textExtractor: ChatResponseTextExtracting = ChatResponseTextExtractor()) {
        self.textExtractor = textExtractor
    }

    func sseSequenceNumber(from dictionary: [String: Any]) -> Int? {
        if let number = dictionary["sequence_number"] as? NSNumber {
            return number.intValue
        }
        if let number = dictionary["sequence_number"] as? Int {
            return number
        }
        if let raw = dictionary["sequence_number"] as? String {
            return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func sseItemID(from dictionary: [String: Any]) -> String? {
        if let itemID = dictionary["item_id"] as? String {
            let trimmed = itemID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let item = dictionary["item"] as? [String: Any],
           let itemID = item["id"] as? String {
            let trimmed = itemID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    func sseItemType(from dictionary: [String: Any]) -> String? {
        guard let item = dictionary["item"] as? [String: Any],
              let type = item["type"] as? String else {
            return nil
        }
        let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    func ssePartType(from dictionary: [String: Any]) -> String? {
        guard let part = dictionary["part"] as? [String: Any],
              let type = part["type"] as? String else {
            return nil
        }
        let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    func openAICompatibleStreamDeltaText(from dictionary: [String: Any]) -> String? {
        func extract(_ value: Any?) -> String? {
            guard let value else { return nil }
            let text = textExtractor.flattenedText(from: value)
            return text.isEmpty ? nil : text
        }

        let itemCandidate: [String: Any]? = {
            guard let item = dictionary["item"] as? [String: Any] else { return nil }
            let itemType = ((item["type"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if itemType == "reasoning" || itemType.contains("tool") {
                return nil
            }
            return item
        }()

        let directCandidates: [Any?] = [
            dictionary["delta"],
            dictionary["text"],
            dictionary["output_text"],
            dictionary["content"],
            itemCandidate?["text"],
            itemCandidate?["output_text"],
            itemCandidate?["content"],
            (dictionary["part"] as? [String: Any])?["text"],
            (dictionary["part"] as? [String: Any])?["content"]
        ]
        for candidate in directCandidates {
            if let text = extract(candidate) {
                return text
            }
        }

        if let choices = dictionary["choices"] as? [[String: Any]] {
            for choice in choices {
                if let delta = choice["delta"] as? [String: Any],
                   let text = extract(delta["content"]) {
                    return text
                }
                if let message = choice["message"] as? [String: Any],
                   let text = extract(message["content"]) {
                    return text
                }
                if let text = extract(choice["text"]) {
                    return text
                }
                if let text = extract(choice["content"]) {
                    return text
                }
            }
        }

        if let response = dictionary["response"] as? [String: Any] {
            if let text = extract(response["output_text"]) {
                return text
            }
            if let text = extract(response["text"]) {
                return text
            }
            if let output = response["output"] as? [[String: Any]],
               let text = textExtractor.extractOpenAIResponseOutputText(output) {
                return text
            }
        }
        return nil
    }

    func openAICompatibleStreamErrorMessage(from dictionary: [String: Any]) -> String? {
        if let error = dictionary["error"] as? [String: Any],
           let message = error["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let response = dictionary["response"] as? [String: Any],
           let error = response["error"] as? [String: Any],
           let message = error["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let message = dictionary["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    func sseStreamErrorMessage(from dictionary: [String: Any]) -> String? {
        if let errorObject = dictionary["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let response = dictionary["response"] as? [String: Any],
           let errorObject = response["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let type = dictionary["type"] as? String,
           type.lowercased().contains("error"),
           let message = dictionary["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        return nil
    }

    func sseStreamErrorMessage(from rawBodyData: Data) -> String? {
        guard !rawBodyData.isEmpty,
              let rawBody = String(data: rawBodyData, encoding: .utf8),
              !rawBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let lines = rawBody.split(whereSeparator: \.isNewline)
        for rawLine in lines {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]",
                  let payloadData = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: payloadData, options: []),
                  let dictionary = object as? [String: Any] else {
                continue
            }
            if let message = sseStreamErrorMessage(from: dictionary) {
                return message
            }
        }

        return nil
    }
}

enum ChatStreamErrorRetryClassifier {
    static func statusCode(from dictionary: [String: Any]) -> Int? {
        let response = dictionary["response"] as? [String: Any]
        let error = (dictionary["error"] as? [String: Any])
            ?? (response?["error"] as? [String: Any])
        let metadata = error?["metadata"] as? [String: Any]
        for rawCode in [error?["code"], dictionary["code"], response?["code"]] {
            if let statusCode = retryableHTTPStatus(from: rawCode) {
                return statusCode
            }
        }
        return statusCode(for: [
            error?["code"] as? String,
            error?["type"] as? String,
            error?["error_type"] as? String,
            metadata?["error_type"] as? String,
            dictionary["type"] as? String,
            dictionary["code"] as? String,
            dictionary["error_type"] as? String,
            response?["error_type"] as? String
        ])
    }

    private static func retryableHTTPStatus(from rawValue: Any?) -> Int? {
        let statusCode: Int?
        if let value = rawValue as? Int {
            statusCode = value
        } else if let value = rawValue as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite,
                  value.doubleValue.rounded(.towardZero) == value.doubleValue {
            statusCode = value.intValue
        } else if let value = rawValue as? String {
            statusCode = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            statusCode = nil
        }
        guard let statusCode,
              NetworkRetryability.shouldRetry(statusCode: statusCode) else {
            return nil
        }
        return statusCode
    }

    static func statusCode(for rawTypes: [String?]) -> Int? {
        let types = Set(rawTypes.compactMap { rawType -> String? in
            guard let rawType else { return nil }
            let normalized = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty ? nil : normalized
        })

        if !types.isDisjoint(with: [
            "rate_limit_exceeded",
            "rate_limit",
            "rate_limit_error",
            "too_many_requests"
        ]) {
            return 429
        }
        if types.contains("overloaded_error") {
            return 529
        }
        if !types.isDisjoint(with: ["server", "server_error", "api_error", "internal_error"]) {
            return 500
        }
        if !types.isDisjoint(with: [
            "timeout",
            "request_timeout",
            "provider_overloaded",
            "provider_unavailable",
            "overloaded",
            "service_unavailable"
        ]) {
            return 503
        }
        return nil
    }
}
