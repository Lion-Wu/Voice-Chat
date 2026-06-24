//
//  ChatService+LMStudioStatefulFallback.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.23.
//

import Foundation

extension ChatService {
    static func isLMStudioMissingPreviousResponseError(
        statusCode: Int?,
        message: String
    ) -> Bool {
        guard statusCode == 400 else { return false }
        let normalized = message.lowercased()
        guard normalized.contains("previous_response_id") else { return false }
        return normalized.contains("could not find stored response")
            || normalized.contains("automatically deleted")
            || normalized.contains("invalid_value")
    }

    func retryLMStudioRequestWithoutPreviousResponseIDIfNeeded(
        statusCode: Int?,
        message: String
    ) -> Bool {
        guard Self.isLMStudioMissingPreviousResponseError(
            statusCode: statusCode,
            message: message
        ) else {
            return false
        }
        guard var context = activeToolLoopContext,
              !context.didRetryWithoutPreviousResponseID,
              context.previousResponseID != nil else {
            return false
        }
        switch context.endpoint.style {
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            break
        case .openAIChatCompletions, .anthropicMessages:
            return false
        }

        context.previousResponseID = nil
        context.didRetryWithoutPreviousResponseID = true

        do {
            let body = try requestBodyBuilder.buildRequestBodyData(
                model: context.model,
                messagePayload: context.currentPayload.messages,
                developerPrompt: context.developerPrompt,
                endpoint: context.endpoint,
                apiAdvancedSettings: configurationProvider.apiAdvancedSettings,
                toolUseSettings: configurationProvider.toolUseSettings,
                previousResponseID: nil,
                thinkingCapability: configurationProvider.thinkingCapability,
                thinkingOption: configurationProvider.thinkingOption
            )
            resetStreamState()
            activeToolLoopContext = context
            activeEndpointCandidate = context.endpoint
            isCancelled = false
            startStreaming(endpoint: context.endpoint, requestBodyData: body)
            return true
        } catch {
            return false
        }
    }
}
