//
//  ChatToolResultMessageEncoder.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

enum ChatToolResultMessageEncoder {
    static func followUpPayload(
        for endpoint: ChatAPIEndpointCandidate,
        originalPayload: [[String: Any]],
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope],
        previousResponseID: String? = nil,
        responsesOutputItems: [[String: Any]] = [],
        anthropicContentBlocks: [[String: Any]] = [],
        chatCompletionsReasoningDetails: [JSONValue] = [],
        chatCompletionsReasoning: String? = nil
    ) -> [[String: Any]] {
        switch endpoint.toolCallingTransport {
        case .anthropicMessagesAPI:
            return anthropicPayload(
                originalPayload: originalPayload,
                calls: calls,
                results: results,
                contentBlocks: anthropicContentBlocks
            )
        case .openAIResponsesAPI:
            return responsesPayload(
                originalPayload: originalPayload,
                calls: calls,
                results: results,
                previousResponseID: previousResponseID,
                outputItems: responsesOutputItems
            )
        case .openAIChatCompletionsAPI:
            return chatCompletionsPayload(
                originalPayload: originalPayload,
                calls: calls,
                results: results,
                reasoningDetails: chatCompletionsReasoningDetails,
                reasoning: chatCompletionsReasoning
            )
        case .promptProtocol:
            return promptToolPayload(
                originalPayload: originalPayload,
                calls: calls,
                results: results,
                previousResponseID: previousResponseID
            )
        }
    }

    static func applyResponsesPreviousResponseID(
        _ responseID: String?,
        to requestBody: inout [String: Any],
        endpoint: ChatAPIEndpointCandidate
    ) {
        guard endpoint.style == .openAIResponses,
              let responseID = ChatRequestBodyProviderEncoder.normalizedPreviousResponseID(
                responseID,
                endpoint: endpoint
              ) else {
            return
        }
        requestBody["previous_response_id"] = responseID
    }

    static func previousResponseIDForToolContinuation(
        _ responseID: String?,
        endpoint: ChatAPIEndpointCandidate,
        settings: ToolUseSettings = .defaults
    ) -> String? {
        guard settings.useProviderContinuationIDs(for: endpoint) else {
            return nil
        }
        return ChatRequestBodyProviderEncoder.normalizedPreviousResponseID(responseID, endpoint: endpoint)
    }

    private static func chatCompletionsPayload(
        originalPayload: [[String: Any]],
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope],
        reasoningDetails: [JSONValue],
        reasoning: String?
    ) -> [[String: Any]] {
        var payload = originalPayload
        var assistantMessage: [String: Any] = [
            "role": "assistant",
            "content": NSNull(),
            "tool_calls": calls.map { call in
                [
                    "id": call.callID,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": call.argumentsJSON
                    ]
                ]
            }
        ]
        if !reasoningDetails.isEmpty {
            assistantMessage["reasoning_details"] = reasoningDetails.map(\.jsonObject)
        } else if let reasoning,
                  !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assistantMessage["reasoning"] = reasoning
        }
        payload.append(assistantMessage)
        for result in results {
            payload.append([
                "role": "tool",
                "tool_call_id": result.callID,
                "content": result.outputJSONString
            ])
        }
        return payload
    }

    private static func responsesPayload(
        originalPayload: [[String: Any]],
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope],
        previousResponseID: String?,
        outputItems: [[String: Any]]
    ) -> [[String: Any]] {
        if previousResponseID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return results.map { result in
                [
                    "type": "function_call_output",
                    "call_id": result.callID,
                    "output": result.outputJSONString
                ]
            }
        }

        var payload = openAIResponsesConversationPayload(from: originalPayload)
        appendOpenAIResponsesOutputItems(outputItems, to: &payload)
        let existingCallIDs = Set(payload.compactMap { $0["call_id"] as? String })
        payload.append(contentsOf: calls.compactMap { call in
            guard !existingCallIDs.contains(call.callID) else { return nil }
            return [
                "type": "function_call",
                "id": call.itemID ?? call.callID,
                "call_id": call.callID,
                "name": call.name,
                "arguments": call.argumentsJSON
            ]
        })
        payload.append(contentsOf: results.map { result in
            [
                "type": "function_call_output",
                "call_id": result.callID,
                "output": result.outputJSONString
            ]
        })
        return payload
    }

    private static func openAIResponsesConversationPayload(from payload: [[String: Any]]) -> [[String: Any]] {
        payload
    }

    private static func appendOpenAIResponsesOutputItems(
        _ outputItems: [[String: Any]],
        to payload: inout [[String: Any]]
    ) {
        for item in outputItems {
            let type = ((item["type"] as? String) ?? "").lowercased()
            guard type == "reasoning" || type == "message" || type == "function_call" else { continue }
            let key = openAIResponsesOutputItemKey(item)
            guard !payload.contains(where: { openAIResponsesOutputItemKey($0) == key }) else { continue }
            payload.append(item)
        }
    }

    private static func openAIResponsesOutputItemKey(_ item: [String: Any]) -> String {
        let type = ((item["type"] as? String) ?? "").lowercased()
        if let id = item["id"] as? String, !id.isEmpty {
            return "\(type):id:\(id)"
        }
        if let callID = item["call_id"] as? String, !callID.isEmpty {
            return "\(type):call_id:\(callID)"
        }
        return "\(type):\(String(describing: item))"
    }

    private static func anthropicPayload(
        originalPayload: [[String: Any]],
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope],
        contentBlocks: [[String: Any]]
    ) -> [[String: Any]] {
        var payload = originalPayload
        let assistantContent = contentBlocks.isEmpty
            ? calls.map { call in
                [
                    "type": "tool_use",
                    "id": call.callID,
                    "name": call.name,
                    "input": parsedJSONObject(call.argumentsJSON) ?? [:]
                ] as [String: Any]
            }
            : contentBlocks
        payload.append([
            "role": "assistant",
            "content": assistantContent
        ])
        payload.append([
            "role": "user",
            "content": results.map { result in
                [
                    "type": "tool_result",
                    "tool_use_id": result.callID,
                    "content": result.outputJSONString,
                    "is_error": result.status != .success
                ]
            }
        ])
        return payload
    }

    private static func promptToolPayload(
        originalPayload: [[String: Any]],
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope],
        previousResponseID: String?
    ) -> [[String: Any]] {
        var payload = originalPayload
        for call in calls {
            payload.append([
                "role": "assistant",
                "content": ChatPromptToolProtocol.toolCallText(for: call)
            ])
        }
        payload.append([
            "role": "user",
            "content": ChatPromptToolProtocol.toolResultText(
                for: results,
                includeContinuationInstruction: previousResponseID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            )
        ])
        return payload
    }

    private static func parsedJSONObject(_ raw: String) -> Any? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
