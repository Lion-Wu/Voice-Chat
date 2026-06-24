//
//  LMStudioPromptToolProtocol.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.23.
//

import Foundation

enum LMStudioPromptToolProtocol {
    static func applyPromptProtocol(
        to requestBody: inout [String: Any],
        definitions: [ChatToolDefinition]
    ) {
        guard !definitions.isEmpty else { return }

        let existingPrompt = (requestBody["system_prompt"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let protocolPrompt = prompt(definitions: definitions)
        requestBody["system_prompt"] = existingPrompt.isEmpty
            ? protocolPrompt
            : "\(existingPrompt)\n\n\(protocolPrompt)"
    }

    static func parseToolCalls(from text: String, provider: ChatProvider?) -> [ChatToolCallEnvelope] {
        for payload in toolCallPayloadCandidates(in: text) {
            if let call = parseToolCallPayload(payload, provider: provider) {
                return [call]
            }
        }
        return []
    }

    static func isDefiniteToolCallStart(_ text: String) -> Bool {
        let probe = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { return false }
        return isDefiniteOpeningToolCallMarker(probe)
    }

    static func canStillBecomeToolCallStart(_ text: String) -> Bool {
        let probe = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { return true }
        return openingToolCallMarkers.contains { marker in
            marker.hasPrefix(probe) || hasOpeningToolCallMarkerPrefix(probe, marker: marker)
        }
    }

    private static func parseToolCallPayload(_ payload: String, provider: ChatProvider?) -> ChatToolCallEnvelope? {
        parseJSONToolCallPayload(payload, provider: provider)
    }

    private static func parseJSONToolCallPayload(_ payload: String, provider: ChatProvider?) -> ChatToolCallEnvelope? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawName = object["name"] as? String else {
            return nil
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let argumentJSON = normalizedArgumentsJSON(from: object["arguments"])

        return ChatToolCallEnvelope(
            callID: UUID().uuidString,
            name: name,
            argumentsJSON: argumentJSON,
            provider: provider
        )
    }

    static func toolCallText(for call: ChatToolCallEnvelope) -> String {
        """
        <tool_call>{"name":"\(escapedJSONString(call.name))","arguments":\(call.argumentsJSON.isEmpty ? "{}" : call.argumentsJSON)}</tool_call>
        """
    }

    static func toolResultText(for results: [ChatToolResultEnvelope]) -> String {
        let blocks = results.map { result in
            """
            <tool_result name="\(escapedXMLAttribute(result.name))">\(result.outputJSONString)</tool_result>
            """
        }
        return """
        \(blocks.joined(separator: "\n"))

        Use the tool result above to answer the user's original request. Do not emit another <tool_call> unless another tool is necessary.
        """
    }

    private static func prompt(definitions: [ChatToolDefinition]) -> String {
        let toolsMetadata = openAIStyleToolsMetadata(definitions: definitions)

        return """
        Local tool use protocol:
        You may request local tools when needed. Available tools metadata:
        \(toolsMetadata)

        To request a tool, your entire message must be exactly one tag:
        <tool_call>{"name":"tool.name","arguments":{}}</tool_call>

        Use valid JSON inside <tool_call>. Do not wrap it in Markdown. Do not add explanations before or after the tag. After a <tool_result> is provided, answer the user normally.
        """
    }

    private static func openAIStyleToolsMetadata(definitions: [ChatToolDefinition]) -> String {
        JSONValue.array(definitions.map { definition in
            .object([
                "type": .string("function"),
                "name": .string(definition.id.rawValue),
                "description": .string(definition.description),
                "parameters": definition.parametersSchema
            ])
        }).compactJSONString
    }

    private static let openingToolCallMarkers = [
        "<tool_call",
        "<|tool_call"
    ]

    private static func toolCallPayloadCandidates(in text: String) -> [String] {
        var candidates: [String] = []

        if let payload = firstAngleTaggedPayload(in: text) {
            candidates.append(payload)
        }
        if let payload = firstPipeTaggedPayload(in: text) {
            candidates.append(payload)
        }

        return candidates
    }

    private static func firstAngleTaggedPayload(in text: String) -> String? {
        let openPrefix = "<tool_call"
        guard let openRange = text.range(of: openPrefix),
              isOpeningToolCallMarkerBoundary(in: text, at: openRange.upperBound) else {
            return nil
        }

        let close = "</tool_call>"
        if let closeRange = text.range(of: close, range: openRange.upperBound..<text.endIndex) {
            return cleanedToolCallPayload(String(text[openRange.upperBound..<closeRange.lowerBound]))
        }

        let payloadStart = indexAfterOpeningMarker(in: text, from: openRange.upperBound)
        return firstJSONObjectString(in: String(text[payloadStart...]))
    }

    private static func firstPipeTaggedPayload(in text: String) -> String? {
        let openPrefix = "<|tool_call"
        var searchRange = text.startIndex..<text.endIndex
        while let openRange = text.range(of: openPrefix, range: searchRange) {
            guard isOpeningToolCallMarkerBoundary(in: text, at: openRange.upperBound) else {
                searchRange = openRange.upperBound..<text.endIndex
                continue
            }

            let payloadStart = indexAfterOpeningMarker(in: text, from: openRange.upperBound)
            return firstJSONObjectString(in: String(text[payloadStart...]))
        }
        return nil
    }

    private static func isDefiniteOpeningToolCallMarker(_ text: String) -> Bool {
        openingToolCallMarkers.contains { marker in
            hasOpeningToolCallMarkerPrefix(text, marker: marker)
        }
    }

    private static func hasOpeningToolCallMarkerPrefix(_ text: String, marker: String) -> Bool {
        guard text.hasPrefix(marker) else { return false }
        let boundaryIndex = text.index(text.startIndex, offsetBy: marker.count)
        return isOpeningToolCallMarkerBoundary(in: text, at: boundaryIndex)
    }

    private static func isOpeningToolCallMarkerBoundary(in text: String, at index: String.Index) -> Bool {
        guard index < text.endIndex else { return true }
        let character = text[index]
        return character == "|" ||
            character == ">" ||
            character == "{" ||
            character.isWhitespace
    }

    private static func indexAfterOpeningMarker(in text: String, from index: String.Index) -> String.Index {
        var current = index
        while current < text.endIndex {
            let character = text[current]
            guard character == "|" || character == ">" || character.isWhitespace else {
                break
            }
            current = text.index(after: current)
        }
        return current
    }

    private static func firstJSONObjectString(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var index = start
        var depth = 0
        var isInString = false
        var isEscaping = false

        while index < text.endIndex {
            let character = text[index]

            if isInString {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInString = false
                }
            } else if character == "\"" {
                isInString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func cleanedToolCallPayload(_ raw: String) -> String {
        var payload = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.first == ">" {
            payload.removeFirst()
            payload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if payload.last == ">" {
            payload.removeLast()
            payload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return payload
    }

    private static func normalizedArgumentsJSON(from value: Any?) -> String {
        switch value {
        case let dictionary as [String: Any]:
            guard JSONSerialization.isValidJSONObject(dictionary),
                  let data = try? JSONSerialization.data(withJSONObject: dictionary),
                  let json = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return json
        case let string as String:
            return normalizedArgumentsJSON(fromRawJSONString: string)
        case .none:
            return "{}"
        default:
            return "{}"
        }
    }

    private static func normalizedArgumentsJSON(fromRawJSONString raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              JSONSerialization.isValidJSONObject(dictionary),
              let normalizedData = try? JSONSerialization.data(withJSONObject: dictionary),
              let normalized = String(data: normalizedData, encoding: .utf8) else {
            return "{}"
        }
        return normalized
    }

    private static func escapedJSONString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return value
        }
        return String(encoded.dropFirst().dropLast())
    }

    private static func escapedXMLAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
