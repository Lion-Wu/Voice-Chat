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
    case lmStudioREST

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .openAIResponses:
            return "OpenAI Responses"
        case .openAIChat:
            return "OpenAI Chat Completions"
        case .anthropic:
            return "Anthropic Messages"
        case .lmStudioREST:
            return "LM Studio REST v1"
        }
    }
}

enum SettingsAdvancedAPIParameterProfile {
    case openAIResponses
    case openAIChat
    case anthropic
    case lmStudioREST

    init(override backend: AdvancedAPIBackendOverrideID) {
        switch backend {
        case .openAIResponses:
            self = .openAIResponses
        case .openAIChat:
            self = .openAIChat
        case .anthropic:
            self = .anthropic
        case .lmStudioREST:
            self = .lmStudioREST
        }
    }

    @MainActor
    init(current context: SettingsAdvancedAPIContext) {
        switch context.currentRequestStyle {
        case .anthropicMessages:
            self = .anthropic
        case .lmStudioRESTV1:
            self = .lmStudioREST
        case .openAIResponses:
            self = .openAIResponses
        case .openAIChatCompletions:
            self = .openAIChat
        }
    }
}
