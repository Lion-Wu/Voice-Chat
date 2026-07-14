//
//  ChatToolSchemaEncoder.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

enum ChatToolSchemaEncoder {
    static func applyToolSchemas(
        to requestBody: inout [String: Any],
        endpoint: ChatAPIEndpointCandidate,
        settings: ToolUseSettings,
        previousResponseID: String? = nil,
        allowedToolIDs: Set<ChatToolID>? = nil
    ) {
        let definitions = ChatToolDefinitions.definitions(enabledIDs: settings.enabledToolIDs)
        guard settings.isEnabled, !definitions.isEmpty else { return }
        applyGeneralToolInstructions(
            to: &requestBody,
            endpoint: endpoint,
            definitions: definitions
        )

        switch endpoint.toolCallingTransport {
        case .openAIResponsesAPI:
            removeOpenAIResponsesJSONMode(from: &requestBody)
            requestBody["tools"] = definitions.map(openAIResponsesTool)
            requestBody["tool_choice"] = openAIResponsesToolChoice(
                definitions: definitions,
                allowedToolIDs: allowedToolIDs
            )

        case .openAIChatCompletionsAPI:
            requestBody.removeValue(forKey: "response_format")
            requestBody["tools"] = definitions.map(openAIChatCompletionsTool)
            requestBody["tool_choice"] = "auto"
            requestBody["parallel_tool_calls"] = false

        case .anthropicMessagesAPI:
            requestBody["tools"] = definitions.map(anthropicTool)

        case .promptProtocol:
            guard !ChatRequestBodyProviderEncoder.isPreviousResponseContinuation(
                previousResponseID: previousResponseID,
                endpoint: endpoint
            ) else {
                return
            }
            ChatPromptToolProtocol.applyPromptProtocol(
                to: &requestBody,
                definitions: definitions
            )
        }
    }

    private static func removeOpenAIResponsesJSONMode(from requestBody: inout [String: Any]) {
        guard var text = requestBody["text"] as? [String: Any] else { return }
        text.removeValue(forKey: "format")
        if text.isEmpty {
            requestBody.removeValue(forKey: "text")
        } else {
            requestBody["text"] = text
        }
    }

    private static func applyGeneralToolInstructions(
        to requestBody: inout [String: Any],
        endpoint: ChatAPIEndpointCandidate,
        definitions: [ChatToolDefinition]
    ) {
        let instruction = ChatToolDefinitions.generalModelInstructions(for: definitions)
        switch endpoint.toolCallingTransport {
        case .openAIResponsesAPI:
            requestBody["instructions"] = appending(instruction, to: requestBody["instructions"] as? String)

        case .openAIChatCompletionsAPI:
            var messages = requestBody["messages"] as? [[String: Any]] ?? []
            if let systemIndex = messages.firstIndex(where: {
                (($0["role"] as? String) ?? "").lowercased() == "system"
            }) {
                messages[systemIndex]["content"] = appending(
                    instruction,
                    to: messages[systemIndex]["content"] as? String
                )
            } else {
                messages.insert(["role": "system", "content": instruction], at: 0)
            }
            requestBody["messages"] = messages

        case .anthropicMessagesAPI:
            requestBody["system"] = appending(instruction, to: requestBody["system"] as? String)

        case .promptProtocol:
            break
        }
    }

    private static func appending(_ instruction: String, to existing: String?) -> String {
        let trimmed = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.contains(instruction) else { return trimmed }
        return trimmed.isEmpty ? instruction : "\(trimmed)\n\n\(instruction)"
    }

    private static func openAIResponsesTool(_ definition: ChatToolDefinition) -> [String: Any] {
        let tool: [String: Any] = [
            "type": "function",
            "name": definition.id.rawValue,
            "description": definition.description,
            "parameters": definition.parametersSchema.jsonObject
        ]
        return tool
    }

    private static func openAIResponsesToolChoice(
        definitions: [ChatToolDefinition],
        allowedToolIDs: Set<ChatToolID>?
    ) -> Any {
        guard let allowedToolIDs, !allowedToolIDs.isEmpty else {
            return "auto"
        }
        let allowedTools = definitions
            .map(\.id)
            .filter(allowedToolIDs.contains)
            .map { id in
                [
                    "type": "function",
                    "name": id.rawValue
                ]
            }
        guard !allowedTools.isEmpty, allowedTools.count < definitions.count else {
            return "auto"
        }
        return [
            "type": "allowed_tools",
            "mode": "auto",
            "tools": allowedTools
        ]
    }

    private static func openAIChatCompletionsTool(_ definition: ChatToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": definition.id.rawValue,
                "description": definition.description,
                "parameters": definition.parametersSchema.jsonObject
            ]
        ]
    }

    private static func anthropicTool(_ definition: ChatToolDefinition) -> [String: Any] {
        [
            "name": definition.id.rawValue,
            "description": definition.description,
            "input_schema": definition.parametersSchema.jsonObject
        ]
    }
}
