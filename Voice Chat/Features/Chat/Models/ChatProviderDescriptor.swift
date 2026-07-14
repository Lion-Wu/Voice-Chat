//
//  ChatProviderDescriptor.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatAPIFormatOption: Identifiable, Sendable {
    let preference: ChatAPIFormatPreference

    var id: String { preference.rawValue }

    var displayName: String {
        ChatProviderDescriptorRegistry.displayName(for: preference)
    }
}

enum ChatProviderDescriptorRegistry {
    static let apiFormatOptions: [ChatAPIFormatOption] = ChatAPIFormatPreference.allCases.map {
        ChatAPIFormatOption(preference: $0)
    }

    static func displayName(for preference: ChatAPIFormatPreference) -> String {
        switch preference {
        case .automatic:
            return NSLocalizedString("Automatic", comment: "Automatic API format preference")
        case .openAIResponses:
            return NSLocalizedString("OpenAI Responses", comment: "API format preference")
        case .openAIChatCompletions:
            return NSLocalizedString("OpenAI Chat Completions", comment: "API format preference")
        case .anthropic, .lmStudio:
            guard let provider = preference.providerHint else {
                return NSLocalizedString("Automatic", comment: "Automatic API format preference")
            }
            return displayName(for: provider)
        }
    }

    static func displayName(for provider: ChatProvider) -> String {
        switch provider {
        case .openAI:
            return NSLocalizedString("OpenAI", comment: "Provider display name")
        case .anthropic:
            return NSLocalizedString("Anthropic", comment: "Provider display name")
        case .lmStudio:
            return NSLocalizedString("LM Studio", comment: "Provider display name")
        case .unknown:
            return NSLocalizedString("Unknown", comment: "Provider display name")
        }
    }
}
