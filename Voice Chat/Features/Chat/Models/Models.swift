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
    case gemini = "gemini"
    case deepSeek = "deepseek"
    case xAI = "xai"
    case openRouter = "openrouter"
    case lmStudio = "lmstudio"
    case llamaCpp = "llama.cpp"
    case openAICompatible = "openai-compatible"
    case unknown = "unknown"

    var displayName: String {
        ChatProviderDescriptorRegistry.displayName(for: self)
    }
}

enum ChatRequestStyle: String, Codable, Sendable {
    case openAIChatCompletions
    case lmStudioRESTV1
    case lmStudioRESTV1LegacyMessage
    case anthropicMessages
}

enum ChatAPIFormatPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case openAI
    case anthropic
    case gemini
    case deepSeek
    case xAI
    case openRouter
    case lmStudio
    case llamaCpp
    case openAICompatible

    var providerHint: ChatProvider? {
        switch self {
        case .automatic:
            return nil
        case .openAI:
            return .openAI
        case .anthropic:
            return .anthropic
        case .gemini:
            return .gemini
        case .deepSeek:
            return .deepSeek
        case .xAI:
            return .xAI
        case .openRouter:
            return .openRouter
        case .lmStudio:
            return .lmStudio
        case .llamaCpp:
            return .llamaCpp
        case .openAICompatible:
            return .openAICompatible
        }
    }

    var requestStyleHint: ChatRequestStyle? {
        switch self {
        case .automatic:
            return nil
        case .openAI, .gemini, .deepSeek, .xAI, .openRouter, .llamaCpp, .openAICompatible:
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
}
