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
        results: [ChatToolResultEnvelope]
    ) -> [[String: Any]] {
        switch endpoint.style {
        case .anthropicMessages:
            return anthropicPayload(originalPayload: originalPayload, calls: calls, results: results)
        case .openAIChatCompletions:
            if ChatRequestBodyEndpointClassifier.isOpenAIResponsesEndpoint(endpoint.chatURL) {
                return responsesPayload(originalPayload: originalPayload, calls: calls, results: results)
            }
            return chatCompletionsPayload(originalPayload: originalPayload, calls: calls, results: results)
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            return lmStudioPromptPayload(originalPayload: originalPayload, calls: calls, results: results)
        }
    }

    static func applyResponsesPreviousResponseID(
        _ responseID: String?,
        to requestBody: inout [String: Any],
        endpoint: ChatAPIEndpointCandidate
    ) {
        guard endpoint.style == .openAIChatCompletions,
              ChatRequestBodyEndpointClassifier.isOpenAIResponsesEndpoint(endpoint.chatURL),
              let responseID,
              !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        requestBody["previous_response_id"] = responseID
    }

    static func previousResponseIDForToolContinuation(
        _ responseID: String?,
        endpoint: ChatAPIEndpointCandidate
    ) -> String? {
        guard endpoint.style == .openAIChatCompletions,
              ChatRequestBodyEndpointClassifier.isOpenAIResponsesEndpoint(endpoint.chatURL) else {
            return responseID
        }
        return nil
    }

    private static func chatCompletionsPayload(
        originalPayload: [[String: Any]],
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope]
    ) -> [[String: Any]] {
        var payload = originalPayload
        payload.append([
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
        ])
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
        results: [ChatToolResultEnvelope]
    ) -> [[String: Any]] {
        var payload = originalPayload
        let existingCallIDs = Set(payload.compactMap { $0["call_id"] as? String })
        payload.append(contentsOf: calls.compactMap { call in
            guard !existingCallIDs.contains(call.callID) else { return nil }
            return [
                "type": "function_call",
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

    private static func anthropicPayload(
        originalPayload: [[String: Any]],
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope]
    ) -> [[String: Any]] {
        var payload = originalPayload
        payload.append([
            "role": "assistant",
            "content": calls.map { call in
                [
                    "type": "tool_use",
                    "id": call.callID,
                    "name": call.name,
                    "input": parsedJSONObject(call.argumentsJSON) ?? [:]
                ]
            }
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

    private static func lmStudioPromptPayload(
        originalPayload: [[String: Any]],
        calls: [ChatToolCallEnvelope],
        results: [ChatToolResultEnvelope]
    ) -> [[String: Any]] {
        var payload = originalPayload
        for call in calls {
            payload.append([
                "role": "assistant",
                "content": LMStudioPromptToolProtocol.toolCallText(for: call)
            ])
        }
        payload.append([
            "role": "user",
            "content": LMStudioPromptToolProtocol.toolResultText(for: results)
        ])
        return payload
    }

    private static func parsedJSONObject(_ raw: String) -> Any? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
