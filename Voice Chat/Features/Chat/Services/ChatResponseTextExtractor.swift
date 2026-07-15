//
//  ChatResponseTextExtractor.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

protocol ChatResponseTextExtracting {
    func extractLMStudioAssistantText(from dictionary: [String: Any]) -> String?
    func extractOpenAIAssistantText(from dictionary: [String: Any]) -> String?
    func extractOpenAIResponseOutputText(_ output: [[String: Any]]) -> String?
    func extractAnthropicAssistantText(from dictionary: [String: Any]) -> String?
    func flattenedText(from value: Any) -> String
}

struct ChatResponseTextExtractor: ChatResponseTextExtracting {
    func extractLMStudioAssistantText(from dictionary: [String: Any]) -> String? {
        if let output = dictionary["output"] as? [[String: Any]],
           let text = extractLMStudioOutputText(output) {
            return text
        }

        if let result = dictionary["result"] as? [String: Any],
           let output = result["output"] as? [[String: Any]],
           let text = extractLMStudioOutputText(output) {
            return text
        }

        if let response = dictionary["response"] as? [String: Any],
           let output = response["output"] as? [[String: Any]],
           let text = extractLMStudioOutputText(output) {
            return text
        }

        return nil
    }

    func extractOpenAIAssistantText(from dictionary: [String: Any]) -> String? {
        if let output = dictionary["output"] as? [[String: Any]],
           let text = extractOpenAIResponseOutputText(output) {
            return text
        }

        if let response = dictionary["response"] as? [String: Any] {
            if let output = response["output"] as? [[String: Any]],
               let text = extractOpenAIResponseOutputText(output) {
                return text
            }
            if let outputText = response["output_text"] {
                let text = flattenedText(from: outputText).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }

        if let item = dictionary["item"] as? [String: Any] {
            let itemType = ((item["type"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if itemType == "reasoning" || itemType.contains("tool") {
                return nil
            }
            if let content = item["content"] {
                let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
            if let textValue = item["text"] {
                let text = flattenedText(from: textValue).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }

        if let choices = dictionary["choices"] as? [[String: Any]] {
            for choice in choices {
                if let message = choice["message"] as? [String: Any],
                   let content = message["content"] {
                    let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                }
                if let delta = choice["delta"] as? [String: Any],
                   let content = delta["content"] {
                    let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                }
            }
        }

        if let outputText = dictionary["output_text"] {
            let text = flattenedText(from: outputText).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        if let textValue = dictionary["text"],
           !isOpenAITextConfiguration(textValue) {
            let text = flattenedText(from: textValue).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        if let content = dictionary["content"] {
            let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        if let message = dictionary["message"] as? [String: Any],
           let content = message["content"] {
            let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private func isOpenAITextConfiguration(_ value: Any) -> Bool {
        guard let dictionary = value as? [String: Any] else { return false }
        return dictionary["format"] != nil &&
            dictionary["text"] == nil &&
            dictionary["content"] == nil
    }

    func extractOpenAIResponseOutputText(_ output: [[String: Any]]) -> String? {
        for item in output {
            let itemType = ((item["type"] as? String) ?? "").lowercased()

            if itemType == "message" || itemType.isEmpty {
                if let content = item["content"] as? [[String: Any]] {
                    let merged = content.compactMap { part -> String? in
                        let partType = ((part["type"] as? String) ?? "").lowercased()
                        guard partType == "output_text" || partType == "text" || partType == "refusal" || partType.isEmpty else {
                            return nil
                        }
                        if let text = part["text"] as? String, !text.isEmpty {
                            return text
                        }
                        if let refusal = part["refusal"] as? String, !refusal.isEmpty {
                            return refusal
                        }
                        if let content = part["content"] as? String, !content.isEmpty {
                            return content
                        }
                        return nil
                    }
                        .joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !merged.isEmpty {
                        return merged
                    }
                }

                if let content = item["content"] {
                    let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                }
            }

            if itemType == "output_text" || itemType == "text" || itemType == "refusal" {
                if let text = item["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                if let refusal = item["refusal"] as? String,
                   !refusal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return refusal
                }
                if let content = item["content"] {
                    let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                }
            }
        }
        return nil
    }

    func extractAnthropicAssistantText(from dictionary: [String: Any]) -> String? {
        if let content = dictionary["content"] as? [[String: Any]] {
            let merged = content
                .compactMap { part -> String? in
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    guard partType == "text" || partType.isEmpty else { return nil }
                    if let text = part["text"] as? String, !text.isEmpty {
                        return text
                    }
                    if let text = part["content"] as? String, !text.isEmpty {
                        return text
                    }
                    return nil
                }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !merged.isEmpty {
                return merged
            }
        }

        if let message = dictionary["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let merged = content
                .compactMap { part -> String? in
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    guard partType == "text" || partType.isEmpty else { return nil }
                    if let text = part["text"] as? String, !text.isEmpty {
                        return text
                    }
                    if let text = part["content"] as? String, !text.isEmpty {
                        return text
                    }
                    return nil
                }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !merged.isEmpty {
                return merged
            }
        }

        return nil
    }

    func flattenedText(from value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any] {
            return array.map(flattenedText(from:)).joined()
        }
        if let dictionary = value as? [String: Any] {
            if let text = dictionary["text"] as? String, !text.isEmpty {
                return text
            }
            if let content = dictionary["content"] as? String, !content.isEmpty {
                return content
            }
            return dictionary.values.map(flattenedText(from:)).joined()
        }
        return ""
    }

    private func extractLMStudioOutputText(_ output: [[String: Any]]) -> String? {
        for item in output {
            let type = ((item["type"] as? String) ?? "").lowercased()
            if type == "reasoning" || type == "tool_call" || type == "invalid_tool_call" {
                continue
            }
            if let content = item["content"] {
                let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
            if let text = item["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if let message = item["message"] {
                let text = flattenedText(from: message).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }
}
