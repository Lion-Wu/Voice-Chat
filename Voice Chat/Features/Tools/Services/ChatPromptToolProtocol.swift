//
//  ChatPromptToolProtocol.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.23.
//

import Foundation

enum ChatPromptToolProtocol {
    private enum ToolCallStartClassification {
        case possible
        case definite
        case normalText
    }

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
        let message = normalizedTransportMessage(text)
        if let call = parseChannelToolCall(from: message, provider: provider) {
            return [call]
        }
        guard isDefiniteOpeningToolCallMarker(message) else { return [] }
        for payload in toolCallPayloadCandidates(in: message) {
            if let call = parseToolCallPayload(payload, provider: provider) {
                return [call]
            }
        }
        return []
    }

    static func isDefiniteToolCallStart(_ text: String) -> Bool {
        let probe = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { return false }
        return toolCallStartClassification(probe) == .definite
    }

    static func canStillBecomeToolCallStart(_ text: String) -> Bool {
        let probe = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { return true }
        return toolCallStartClassification(probe) != .normalText
    }

    private static func toolCallStartClassification(_ text: String) -> ToolCallStartClassification {
        if harmonyAssistantStartMarker.hasPrefix(text) {
            return .possible
        }
        let probe = normalizedTransportMessage(text)
        guard !probe.isEmpty else { return .possible }
        if isDefiniteOpeningToolCallMarker(probe) {
            return .definite
        }
        if openingToolCallMarkers.contains(where: { $0.hasPrefix(probe) }) {
            return .possible
        }
        if channelMarker.hasPrefix(probe) {
            return .possible
        }
        guard probe.hasPrefix(channelMarker) else {
            return .normalText
        }
        if channelRecipient(in: probe, requiresTerminator: true) != nil {
            return .definite
        }
        return probe.contains(channelMessageMarker) ? .normalText : .possible
    }

    private static func normalizedTransportMessage(_ text: String) -> String {
        var message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.hasPrefix(harmonyAssistantStartMarker) {
            message.removeFirst(harmonyAssistantStartMarker.count)
            message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return message
    }

    private static func parseChannelToolCall(
        from message: String,
        provider: ChatProvider?
    ) -> ChatToolCallEnvelope? {
        guard message.hasPrefix(channelMarker),
              let name = channelRecipient(in: message, requiresTerminator: false),
              let messageRange = message.range(of: channelMessageMarker) else {
            return nil
        }

        let rawContent = String(message[messageRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let payload = firstJSONObjectString(in: rawContent),
           let data = payload.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["name"] is String,
           object.keys.contains("arguments") {
            guard let call = parseJSONToolCallPayload(payload, provider: provider),
                  protocolEnvelopeRecipients.contains(name) || name == call.name else {
                return nil
            }
            return call
        }
        guard !protocolEnvelopeRecipients.contains(name) else { return nil }

        let argumentsJSON: String
        if rawContent.isEmpty || rawContent.hasPrefix("<|call|>") {
            argumentsJSON = "{}"
        } else {
            guard let rawArguments = firstJSONObjectString(in: rawContent),
                  let normalized = normalizedArgumentsJSON(fromRawJSONString: rawArguments) else {
                return nil
            }
            argumentsJSON = normalized
        }

        return ChatToolCallEnvelope(
            callID: UUID().uuidString,
            name: name,
            argumentsJSON: argumentsJSON,
            provider: provider
        )
    }

    private static func channelRecipient(in text: String, requiresTerminator: Bool) -> String? {
        guard text.hasPrefix(channelMarker) else { return nil }
        let headerEnd = text.range(of: channelMessageMarker)?.lowerBound ?? text.endIndex
        let headerStart = text.index(text.startIndex, offsetBy: channelMarker.count)
        guard headerStart <= headerEnd else { return nil }
        let header = String(text[headerStart..<headerEnd])
        guard let recipientMarker = header.range(of: "to=") else { return nil }
        if recipientMarker.lowerBound > header.startIndex {
            let previous = header[header.index(before: recipientMarker.lowerBound)]
            guard previous.isWhitespace else { return nil }
        }

        var recipient = header[recipientMarker.upperBound...]
        while recipient.first?.isWhitespace == true {
            recipient = recipient.dropFirst()
        }
        if recipient.hasPrefix("tool ") {
            recipient = recipient.dropFirst("tool ".count)
        }

        var nameEnd = recipient.startIndex
        while nameEnd < recipient.endIndex, isToolNameCharacter(recipient[nameEnd]) {
            nameEnd = recipient.index(after: nameEnd)
        }
        guard nameEnd > recipient.startIndex else { return nil }
        if requiresTerminator {
            guard nameEnd < recipient.endIndex else { return nil }
            let terminator = recipient[nameEnd]
            guard terminator.isWhitespace || terminator == "<" else { return nil }
        }

        let rawName = String(recipient[..<nameEnd])
        return normalizedChannelRecipient(rawName)
    }

    private static func isToolNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "." || character == "-"
    }

    private static func normalizedChannelRecipient(_ rawName: String) -> String? {
        let prefixes = ["functions.", "tools.", "tool."]
        let name = prefixes.first(where: { rawName.hasPrefix($0) })
            .map { String(rawName.dropFirst($0.count)) } ?? rawName
        return name.isEmpty ? nil : name
    }

    private static func parseToolCallPayload(_ payload: String, provider: ChatProvider?) -> ChatToolCallEnvelope? {
        parseJSONToolCallPayload(payload, provider: provider) ??
            parseShorthandToolCallPayload(payload, provider: provider)
    }

    private static func parseJSONToolCallPayload(_ payload: String, provider: ChatProvider?) -> ChatToolCallEnvelope? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawName = object["name"] as? String else {
            return nil
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let argumentJSON: String
        if object.keys.contains("arguments") {
            guard let normalized = normalizedArgumentsJSON(from: object["arguments"]) else {
                return nil
            }
            argumentJSON = normalized
        } else {
            argumentJSON = "{}"
        }

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

    static func toolResultText(
        for results: [ChatToolResultEnvelope],
        includeContinuationInstruction: Bool = true
    ) -> String {
        let blocks = results.map { result in
            """
            <tool_result name="\(escapedXMLAttribute(result.name))">\(escapedToolResultJSON(result.outputJSONString))</tool_result>
            """
        }
        guard includeContinuationInstruction else {
            return blocks.joined(separator: "\n")
        }
        return """
        \(blocks.joined(separator: "\n"))

        \(ChatToolDefinitions.untrustedResultInstruction) Do not emit another <tool_call> unless another tool is necessary.
        """
    }

    private static func prompt(definitions: [ChatToolDefinition]) -> String {
        let toolsMetadata = openAIStyleToolsMetadata(definitions: definitions)

        return """
        \(ChatToolDefinitions.generalModelInstructions(for: definitions))

        Available functions:
        \(toolsMetadata)

        Function-call rules:
        - Call at most one function in each assistant turn.
        - To call a function, make the complete assistant message exactly this single block:
        <tool_call>{"name":"exact_function_name","arguments":{}}</tool_call>
        - "name" must exactly match one available function. "arguments" must be one JSON object that satisfies that function's parameters schema.
        - Do not wrap the block in Markdown. Do not add user-facing text, explanations, or a simulated function result before or after it.
        - Follow the selected function's description and schema. If several functions are needed, call them one at a time across successive <tool_result> turns. Never assume an unlisted function is available.
        - The app executes the function and returns <tool_result> data. After receiving it, answer the original request normally, or call one more function only when necessary.
        """
    }

    private static func openAIStyleToolsMetadata(definitions: [ChatToolDefinition]) -> String {
        JSONValue.array(definitions.map { definition in
            .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string(definition.id.rawValue),
                    "description": .string(definition.description),
                    "parameters": definition.parametersSchema
                ])
            ])
        }).compactJSONString
    }

    private static let openingToolCallMarkers = [
        "<tool_call",
        "<|tool_call"
    ]
    private static let channelMarker = "<|channel|>"
    private static let channelMessageMarker = "<|message|>"
    private static let harmonyAssistantStartMarker = "<|start|>assistant"
    private static let protocolEnvelopeRecipients: Set<String> = ["tool_call", "tool_use"]

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
        let remaining = String(text[payloadStart...])
        return firstShorthandToolCallString(in: remaining) ?? firstJSONObjectString(in: remaining)
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
            let remaining = String(text[payloadStart...])
            return firstShorthandToolCallString(in: remaining) ?? firstJSONObjectString(in: remaining)
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

    private static func firstShorthandToolCallString(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("call:") else { return nil }

        let nameStart = trimmed.index(trimmed.startIndex, offsetBy: "call:".count)
        var nameEnd = nameStart
        while nameEnd < trimmed.endIndex {
            let character = trimmed[nameEnd]
            if character.isLetter || character.isNumber || character == "_" || character == "." || character == "-" {
                nameEnd = trimmed.index(after: nameEnd)
            } else {
                break
            }
        }
        guard nameEnd > nameStart else { return nil }

        let name = String(trimmed[nameStart..<nameEnd])
        let remainder = String(trimmed[nameEnd...])
        let arguments = firstJSONObjectString(in: remainder) ?? "{}"
        return "call:\(name)\(arguments)"
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

    private static func normalizedArgumentsJSON(from value: Any?) -> String? {
        switch value {
        case let dictionary as [String: Any]:
            guard JSONSerialization.isValidJSONObject(dictionary),
                  let data = try? JSONSerialization.data(withJSONObject: dictionary),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        case let string as String:
            return normalizedArgumentsJSON(fromRawJSONString: string)
        default:
            return nil
        }
    }

    private static func normalizedArgumentsJSON(fromRawJSONString raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              JSONSerialization.isValidJSONObject(dictionary),
              let normalizedData = try? JSONSerialization.data(withJSONObject: dictionary),
              let normalized = String(data: normalizedData, encoding: .utf8) else {
            return nil
        }
        return normalized
    }

    private static func parseShorthandToolCallPayload(_ payload: String, provider: ChatProvider?) -> ChatToolCallEnvelope? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("call:") else { return nil }

        let nameStart = trimmed.index(trimmed.startIndex, offsetBy: "call:".count)
        var nameEnd = nameStart
        while nameEnd < trimmed.endIndex {
            let character = trimmed[nameEnd]
            if character.isLetter || character.isNumber || character == "_" || character == "." || character == "-" {
                nameEnd = trimmed.index(after: nameEnd)
            } else {
                break
            }
        }
        let name = String(trimmed[nameStart..<nameEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let rawArguments = firstJSONObjectString(in: String(trimmed[nameEnd...]))
        let argumentsJSON: String
        if let rawArguments {
            guard let normalized = normalizedArgumentsJSON(fromRawJSONString: rawArguments) else {
                return nil
            }
            argumentsJSON = normalized
        } else {
            argumentsJSON = "{}"
        }
        return ChatToolCallEnvelope(
            callID: UUID().uuidString,
            name: name,
            argumentsJSON: argumentsJSON,
            provider: provider
        )
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

    private static func escapedToolResultJSON(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")
    }
}
