//
//  ChatNetworkModels.swift
//  Voice Chat
//
//  Created as part of MVVM restructuring.
//

import Foundation

// MARK: - Streaming Chunk Models

struct ChatCompletionChunk: Codable {
    var id: String?
    var object: String?
    var created: Int?
    var model: String?
    var choices: [Choice]?
}

struct Choice: Codable {
    var index: Int?
    var finishReason: String?
    var delta: Delta?

    private enum CodingKeys: String, CodingKey {
        case index
        case finishReason = "finish_reason"
        case delta
    }
}

/// Value type that normalizes reasoning payloads in streaming responses.
struct ReasoningValue: Codable {
    let text: String

    init(from decoder: Decoder) throws {
        if let single = try? String(from: decoder) {
            self.text = single
            return
        }
        if let object = try? AnyDictionary(from: decoder) {
            if let value = object.storage["content"]?.stringValue ?? object.storage["text"]?.stringValue {
                self.text = value
                return
            }
            let joined = object.storage.values.compactMap { $0.stringValue }.joined()
            if !joined.isEmpty {
                self.text = joined
                return
            }
        }
        if let array = try? [AnyDictionary](from: decoder) {
            let collected = array.compactMap { item in
                item.storage["content"]?.stringValue ?? item.storage["text"]?.stringValue
            }.joined()
            self.text = collected
            return
        }
        self.text = ""
    }
}

struct AnyDecodableValue: Decodable {
    let value: Any

    var stringValue: String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let object = try? AnyDictionary(from: decoder) {
            value = object.storage
        } else if let array = try? [AnyDecodableValue](from: decoder) {
            value = array.map { $0.value }
        } else {
            value = NSNull()
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    var intValue: Int? { nil }

    init?(intValue: Int) {
        return nil
    }
}

struct AnyDictionary: Decodable {
    let storage: [String: AnyDecodableValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var result: [String: AnyDecodableValue] = [:]
        for key in container.allKeys {
            result[key.stringValue] = try container.decode(AnyDecodableValue.self, forKey: key)
        }
        self.storage = result
    }
}

struct Delta: Codable {
    var role: String?
    var content: String?
    var reasoning: ReasoningValue?
}

enum ChatNetworkError: Error {
    case invalidURL
    case serverError(String)
    case timeout(String)
}
