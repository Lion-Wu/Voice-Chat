//
//  ChatRequestBodyBuilder.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import CryptoKit
import Foundation

protocol ChatRequestBodyBuilding: Sendable {
    func buildRequestBodyData(
        model: String,
        messagePayload: [[String: Any]],
        developerPrompt: String?,
        endpoint: ChatAPIEndpointCandidate,
        apiAdvancedSettings: APIAdvancedSettings,
        toolUseSettings: ToolUseSettings,
        previousResponseID: String?,
        thinkingCapability: ModelThinkingCapability?,
        thinkingOption: ModelThinkingOption?
    ) throws -> Data
}

struct ChatRequestBodyBuilder: ChatRequestBodyBuilding, Sendable {
    private let advancedConfigurationApplier: ChatRequestAdvancedConfigurationApplier
    private let thinkingConfigurationApplier: ChatRequestThinkingConfigurationApplier

    init(
        advancedConfigurationApplier: ChatRequestAdvancedConfigurationApplier = ChatRequestAdvancedConfigurationApplier(),
        thinkingConfigurationApplier: ChatRequestThinkingConfigurationApplier = ChatRequestThinkingConfigurationApplier()
    ) {
        self.advancedConfigurationApplier = advancedConfigurationApplier
        self.thinkingConfigurationApplier = thinkingConfigurationApplier
    }

    func buildRequestBodyData(
        model: String,
        messagePayload: [[String: Any]],
        developerPrompt: String?,
        endpoint: ChatAPIEndpointCandidate,
        apiAdvancedSettings: APIAdvancedSettings,
        toolUseSettings: ToolUseSettings = .defaults,
        previousResponseID: String? = nil,
        thinkingCapability: ModelThinkingCapability?,
        thinkingOption: ModelThinkingOption?
    ) throws -> Data {
        let settings = apiAdvancedSettings.sanitized
        let effectivePreviousResponseID = toolUseSettings.useProviderContinuationIDs(for: endpoint)
            ? ChatRequestBodyProviderEncoder.normalizedPreviousResponseID(previousResponseID, endpoint: endpoint)
            : nil
        var requestBody = ChatRequestBodyProviderEncoder.makeBaseRequestBody(
            model: model,
            messagePayload: messagePayload,
            developerPrompt: developerPrompt,
            endpoint: endpoint,
            apiAdvancedSettings: settings,
            previousResponseID: effectivePreviousResponseID
        )
        advancedConfigurationApplier.apply(to: &requestBody, model: model, endpoint: endpoint, settings: settings)
        thinkingConfigurationApplier.apply(
            to: &requestBody,
            model: model,
            endpoint: endpoint,
            settings: settings,
            thinkingCapability: thinkingCapability,
            thinkingOption: thinkingOption
        )
        ChatToolSchemaEncoder.applyToolSchemas(
            to: &requestBody,
            endpoint: endpoint,
            settings: toolUseSettings,
            previousResponseID: effectivePreviousResponseID,
            allowedToolIDs: nil
        )
        ChatToolResultMessageEncoder.applyResponsesPreviousResponseID(
            effectivePreviousResponseID,
            to: &requestBody,
            endpoint: endpoint
        )
        OpenAIPromptCacheRequestOptions.apply(
            to: &requestBody,
            model: model,
            endpoint: endpoint
        )
        return try JSONSerialization.data(withJSONObject: requestBody, options: [.sortedKeys])
    }
}

private enum OpenAIPromptCacheRequestOptions {
    static func apply(
        to requestBody: inout [String: Any],
        model: String,
        endpoint: ChatAPIEndpointCandidate
    ) {
        guard isOfficialOpenAIEndpoint(endpoint) else { return }
        switch endpoint.style {
        case .openAIResponses, .openAIChatCompletions:
            break
        case .lmStudioRESTV1, .anthropicMessages:
            return
        }

        requestBody["prompt_cache_key"] = promptCacheKey(
            for: requestBody,
            model: model,
            endpoint: endpoint
        )
    }

    private static func isOfficialOpenAIEndpoint(_ endpoint: ChatAPIEndpointCandidate) -> Bool {
        let host = (endpoint.chatURL.host ?? "").lowercased()
        return ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "openai.com")
    }

    private static func promptCacheKey(
        for requestBody: [String: Any],
        model: String,
        endpoint: ChatAPIEndpointCandidate
    ) -> String {
        var staticBody = requestBody
        staticBody.removeValue(forKey: "input")
        if endpoint.style == .openAIChatCompletions,
           let messages = requestBody["messages"] as? [[String: Any]] {
            let staticPrefix = messages.prefix { message in
                let role = ((message["role"] as? String) ?? "").lowercased()
                return role == "system" || role == "developer"
            }
            if staticPrefix.isEmpty {
                staticBody.removeValue(forKey: "messages")
            } else {
                staticBody["messages"] = Array(staticPrefix)
            }
        } else {
            staticBody.removeValue(forKey: "messages")
        }
        staticBody.removeValue(forKey: "previous_response_id")
        staticBody.removeValue(forKey: "tool_choice")
        staticBody.removeValue(forKey: "prompt_cache_key")
        staticBody.removeValue(forKey: "prompt_cache_retention")

        let payload: [String: Any] = [
            "version": 2,
            "endpoint_style": endpoint.style.rawValue,
            "chat_url": endpoint.chatURL.absoluteString,
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "static_request_body": staticBody
        ]
        let digest = sha256Hex(of: payload)
        return "voice-chat-\(digest.prefix(53))"
    }

    private static func sha256Hex(of value: Any) -> String {
        let data: Data
        if JSONSerialization.isValidJSONObject(value),
           let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            data = encoded
        } else {
            data = Data(String(describing: value).utf8)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
