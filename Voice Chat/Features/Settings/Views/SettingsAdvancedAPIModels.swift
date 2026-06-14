//
//  SettingsAdvancedAPIModels.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import SwiftUI

enum AdvancedAPISettingsSectionID: String, CaseIterable, Identifiable {
    case metadata
    case currentBackend
    case backendOverrides
    case defaults

    var id: String { rawValue }
}

enum AdvancedAPIBackendOverrideID: String, CaseIterable, Identifiable {
    case openAIResponses
    case openAIChat
    case anthropic
    case gemini
    case deepSeek
    case xAI
    case openRouter
    case lmStudioREST
    case lmStudioOpenAICompatible
    case llamaCpp
    case genericOpenAICompatible

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .openAIResponses:
            return "OpenAI Responses"
        case .openAIChat:
            return "OpenAI Chat Completions"
        case .anthropic:
            return "Anthropic Messages"
        case .gemini:
            return "Gemini OpenAI Compatibility"
        case .deepSeek:
            return "DeepSeek Chat Completions"
        case .xAI:
            return "xAI Chat Completions"
        case .openRouter:
            return "OpenRouter Chat Completions"
        case .lmStudioREST:
            return "LM Studio REST v1"
        case .lmStudioOpenAICompatible:
            return "LM Studio OpenAI Compatibility"
        case .llamaCpp:
            return "llama.cpp OpenAI Compatibility"
        case .genericOpenAICompatible:
            return "Generic OpenAI Compatible"
        }
    }
}

enum SettingsAdvancedAPIParameterProfile {
    case openAIResponses
    case openAIChat
    case openAICompatible
    case anthropic
    case gemini
    case deepSeek
    case xAI
    case openRouter
    case lmStudioREST
    case lmStudioOpenAICompatible
    case llamaCpp

    init(override backend: AdvancedAPIBackendOverrideID) {
        switch backend {
        case .openAIResponses:
            self = .openAIResponses
        case .openAIChat:
            self = .openAIChat
        case .anthropic:
            self = .anthropic
        case .gemini:
            self = .gemini
        case .deepSeek:
            self = .deepSeek
        case .xAI:
            self = .xAI
        case .openRouter:
            self = .openRouter
        case .lmStudioREST:
            self = .lmStudioREST
        case .lmStudioOpenAICompatible:
            self = .lmStudioOpenAICompatible
        case .llamaCpp:
            self = .llamaCpp
        case .genericOpenAICompatible:
            self = .openAICompatible
        }
    }

    @MainActor
    init(current context: SettingsAdvancedAPIContext) {
        switch context.currentRequestStyle {
        case .anthropicMessages:
            self = .anthropic
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            self = .lmStudioREST
        case .openAIChatCompletions:
            self = Self.openAICompatibleProfile(context: context)
        }
    }

    @MainActor
    private static func openAICompatibleProfile(context: SettingsAdvancedAPIContext) -> Self {
        if context.isCurrentOpenAIResponsesEndpoint {
            return .openAIResponses
        }

        switch context.currentProvider {
        case .openAI:
            return .openAIChat
        case .gemini:
            return .gemini
        case .deepSeek:
            return .deepSeek
        case .xAI:
            return .xAI
        case .openRouter:
            return .openRouter
        case .lmStudio:
            return .lmStudioOpenAICompatible
        case .llamaCpp:
            return .llamaCpp
        case .openAICompatible, .unknown, .anthropic:
            return .openAICompatible
        }
    }
}
