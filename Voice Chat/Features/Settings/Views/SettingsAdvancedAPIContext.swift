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
            ?? .unknown
    }

    var currentRequestStyle: ChatRequestStyle {
        let base = viewModel.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.selectedChatAPIFormatPreference.requestStyleHint
            ?? settingsManager.chatModelCapabilities.detectedRequestStyle(for: base)
            ?? SettingsAPIRequestStyleResolver.inferredStyle(
                for: base,
                providerHint: currentProvider
            )
            ?? .openAIResponses
    }

    var currentRequestStyleDisplayName: String {
        switch currentRequestStyle {
        case .openAIResponses:
            return currentProvider == .unknown
                ? String(localized: "Unknown, using OpenAI Responses")
                : String(localized: "OpenAI Responses")
        case .openAIChatCompletions:
            return String(localized: "OpenAI Chat Completions")
        case .lmStudioRESTV1:
            return String(localized: "LM Studio REST v1")
        case .anthropicMessages:
            return String(localized: "Anthropic Messages")
        }
    }

    var selectedAPIFormatDisplayName: String {
        switch viewModel.selectedChatAPIFormatPreference {
        case .automatic:
            return String(localized: "Automatic")
        case .openAIResponses:
            return String(localized: "OpenAI Responses")
        case .openAIChatCompletions:
            return String(localized: "OpenAI Chat Completions")
        case .anthropic:
            return ChatProvider.anthropic.displayName
        case .lmStudio:
            return ChatProvider.lmStudio.displayName
        }
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

enum SettingsAPIRequestStyleResolver {
    static func inferredStyle(
        for baseURL: String,
        providerHint: ChatProvider? = nil
    ) -> ChatRequestStyle? {
        DefaultChatEndpointResolver()
            .streamingCandidates(
                for: baseURL,
                providerHint: providerHint,
                styleHint: nil
            )
            .first?
            .style
    }
}
