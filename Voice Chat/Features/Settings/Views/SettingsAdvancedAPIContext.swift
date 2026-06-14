//
//  SettingsAdvancedAPIContext.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

@MainActor
struct SettingsAdvancedAPIContext {
    let viewModel: SettingsViewModel
    let settingsManager: SettingsManager

    var currentProvider: ChatProvider {
        let base = viewModel.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.selectedChatAPIFormatPreference.providerHint
            ?? settingsManager.chatModelCapabilities.detectedProvider(for: base)
            ?? ChatAPIEndpointResolver.officialProviderHint(for: base)
            ?? .openAICompatible
    }

    var currentRequestStyle: ChatRequestStyle {
        let base = viewModel.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.selectedChatAPIFormatPreference.requestStyleHint
            ?? settingsManager.chatModelCapabilities.detectedRequestStyle(for: base)
            ?? .openAIChatCompletions
    }

    var currentRequestStyleDisplayName: String {
        switch currentRequestStyle {
        case .openAIChatCompletions:
            return isCurrentOpenAIResponsesEndpoint ? String(localized: "OpenAI Responses") : String(localized: "OpenAI Chat Completions")
        case .lmStudioRESTV1:
            return String(localized: "LM Studio REST v1")
        case .lmStudioRESTV1LegacyMessage:
            return String(localized: "LM Studio REST legacy message")
        case .anthropicMessages:
            return String(localized: "Anthropic Messages")
        }
    }

    var selectedAPIFormatDisplayName: String {
        switch viewModel.selectedChatAPIFormatPreference {
        case .automatic:
            return String(localized: "Automatic")
        case .openAI:
            return ChatProvider.openAI.displayName
        case .anthropic:
            return ChatProvider.anthropic.displayName
        case .gemini:
            return ChatProvider.gemini.displayName
        case .deepSeek:
            return ChatProvider.deepSeek.displayName
        case .xAI:
            return ChatProvider.xAI.displayName
        case .openRouter:
            return ChatProvider.openRouter.displayName
        case .lmStudio:
            return ChatProvider.lmStudio.displayName
        case .llamaCpp:
            return ChatProvider.llamaCpp.displayName
        case .openAICompatible:
            return ChatProvider.openAICompatible.displayName
        }
    }

    var isCurrentOpenAIResponsesEndpoint: Bool {
        guard currentRequestStyle == .openAIChatCompletions else { return false }
        if let endpoint = viewModel.lastModelFetchEndpoint {
            return endpoint.chatURL.path.lowercased().hasSuffix("/responses")
        }
        return viewModel.apiURL.lowercased().contains("/responses")
    }

    var selectedModelMetadata: ModelInfo? {
        viewModel.lastFetchedModelMetadata.first { $0.id == viewModel.selectedModel }
    }

    var localizedUnknown: String {
        String(localized: "Unknown")
    }

    func joined(_ values: [String]?) -> String {
        guard let values, !values.isEmpty else { return String(localized: "None") }
        return values.joined(separator: ", ")
    }

    func optionalBool(_ value: Bool?) -> String {
        guard let value else { return localizedUnknown }
        return value ? String(localized: "Yes") : String(localized: "No")
    }
}
