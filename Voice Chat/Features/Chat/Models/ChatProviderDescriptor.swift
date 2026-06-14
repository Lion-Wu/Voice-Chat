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
        guard let provider = preference.providerHint else {
            return NSLocalizedString("Automatic", comment: "Automatic API format preference")
        }
        return displayName(for: provider)
    }

    static func displayName(for provider: ChatProvider) -> String {
        switch provider {
        case .openAI:
            return NSLocalizedString("OpenAI", comment: "Provider display name")
        case .anthropic:
            return NSLocalizedString("Anthropic", comment: "Provider display name")
        case .gemini:
            return NSLocalizedString("Gemini", comment: "Provider display name")
        case .deepSeek:
            return NSLocalizedString("DeepSeek", comment: "Provider display name")
        case .xAI:
            return NSLocalizedString("xAI", comment: "Provider display name")
        case .openRouter:
            return NSLocalizedString("OpenRouter", comment: "Provider display name")
        case .lmStudio:
            return NSLocalizedString("LM Studio", comment: "Provider display name")
        case .llamaCpp:
            return NSLocalizedString("llama.cpp", comment: "Provider display name")
        case .openAICompatible:
            return NSLocalizedString("OpenAI Compatible", comment: "Provider display name")
        case .unknown:
            return NSLocalizedString("Unknown", comment: "Provider display name")
        }
    }
}
