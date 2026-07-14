//
//  Models.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//

import Foundation

enum ChatProvider: String, Codable, Sendable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case lmStudio = "lmstudio"
    case unknown = "unknown"

    var displayName: String {
        ChatProviderDescriptorRegistry.displayName(for: self)
    }
}

enum ChatRequestStyle: String, Codable, Sendable {
    case openAIResponses
    case openAIChatCompletions
    case lmStudioRESTV1
    case anthropicMessages

    var toolCallingTransport: ChatToolCallingTransport {
        switch self {
        case .openAIResponses:
            return .openAIResponsesAPI
        case .openAIChatCompletions:
            return .openAIChatCompletionsAPI
        case .anthropicMessages:
            return .anthropicMessagesAPI
        case .lmStudioRESTV1:
            return .promptProtocol
        }
    }
}

enum ChatToolCallingTransport: Equatable, Sendable {
    case openAIResponsesAPI
    case openAIChatCompletionsAPI
    case anthropicMessagesAPI
    case promptProtocol
}

enum ChatAPIFormatPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case openAIResponses
    case openAIChatCompletions
    case anthropic
    case lmStudio

    var providerHint: ChatProvider? {
        switch self {
        case .automatic:
            return nil
        case .openAIResponses, .openAIChatCompletions:
            return .openAI
        case .anthropic:
            return .anthropic
        case .lmStudio:
            return .lmStudio
        }
    }

    var requestStyleHint: ChatRequestStyle? {
        switch self {
        case .automatic:
            return nil
        case .openAIResponses:
            return .openAIResponses
        case .openAIChatCompletions:
            return .openAIChatCompletions
        case .anthropic:
            return .anthropicMessages
        case .lmStudio:
            return .lmStudioRESTV1
        }
    }

}

struct ChatAPIEndpointCandidate: Hashable, Sendable {
    let provider: ChatProvider
    let style: ChatRequestStyle
    let chatURL: URL
    let modelsURL: URL

    var toolCallingTransport: ChatToolCallingTransport {
        style.toolCallingTransport
    }
}
