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
        settings: ToolUseSettings
    ) {
        let definitions = ChatToolDefinitions.definitions(enabledIDs: settings.enabledToolIDs(for: endpoint))
        guard settings.isEnabled, !definitions.isEmpty else { return }

        switch endpoint.style {
        case .openAIChatCompletions:
            if ChatRequestBodyEndpointClassifier.isOpenAIResponsesEndpoint(endpoint.chatURL) {
                requestBody["tools"] = definitions.map(openAIResponsesTool)
                requestBody["tool_choice"] = "auto"
            } else {
                requestBody["tools"] = definitions.map(openAIChatCompletionsTool)
                requestBody["tool_choice"] = "auto"
                requestBody["parallel_tool_calls"] = false
            }

        case .anthropicMessages:
            requestBody["tools"] = definitions.map(anthropicTool)

        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            LMStudioPromptToolProtocol.applyPromptProtocol(
                to: &requestBody,
                definitions: definitions
            )
        }
    }

    private static func openAIResponsesTool(_ definition: ChatToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "name": definition.id.rawValue,
            "description": definition.description,
            "parameters": definition.parametersSchema.jsonObject
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
