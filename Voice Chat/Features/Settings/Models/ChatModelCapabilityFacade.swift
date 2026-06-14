//
//  ChatModelCapabilityFacade.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

@MainActor
struct ChatModelCapabilityFacade {
    var store: ChatModelCapabilityStore
    var chatSettings: ChatSettings
    var chatServerPresets: [ChatServerPreset]
    var selectedChatServerPresetID: UUID?

    mutating func updateImageInputSupport(_ supportByModel: [String: Bool], for apiBaseURL: String) {
        store.updateImageInputSupport(supportByModel, for: apiBaseURL)
    }

    mutating func updateThinkingCapabilities(
        _ capabilitiesByModel: [String: ModelThinkingCapability],
        for apiBaseURL: String
    ) {
        store.updateThinkingCapabilities(capabilitiesByModel, for: apiBaseURL)
    }

    mutating func noteDetectedProvider(_ provider: ChatProvider, for apiBaseURL: String) {
        store.noteDetectedProvider(provider, for: apiBaseURL)
    }

    mutating func noteDetectedRequestStyle(_ style: ChatRequestStyle, for apiBaseURL: String) {
        store.noteDetectedRequestStyle(style, for: apiBaseURL)
    }

    mutating func noteDetectedEndpoint(_ endpoint: ChatAPIEndpointCandidate, for apiBaseURL: String) {
        store.noteDetectedEndpoint(endpoint, for: apiBaseURL)
    }

    func detectedProvider(for apiBaseURL: String) -> ChatProvider? {
        store.detectedProvider(for: apiBaseURL)
    }

    func detectedRequestStyle(for apiBaseURL: String) -> ChatRequestStyle? {
        store.detectedRequestStyle(for: apiBaseURL)
    }

    func chatAPIFormatPreference(for presetID: UUID?) -> ChatAPIFormatPreference {
        ChatServerPresetStore.apiFormatPreference(for: presetID, in: chatServerPresets)
    }

    func selectedChatAPIFormatPreference() -> ChatAPIFormatPreference {
        chatAPIFormatPreference(for: selectedChatServerPresetID)
    }

    func resolvedProvider(for apiBaseURL: String) -> ChatProvider? {
        if let manualPreference = manualChatAPIFormatPreference(for: apiBaseURL),
           let provider = manualPreference.providerHint {
            return provider
        }
        return detectedProvider(for: apiBaseURL)
    }

    func resolvedRequestStyle(for apiBaseURL: String) -> ChatRequestStyle? {
        if let manualPreference = manualChatAPIFormatPreference(for: apiBaseURL),
           let style = manualPreference.requestStyleHint {
            return style
        }
        return detectedRequestStyle(for: apiBaseURL)
    }

    func imageInputManualOverride(for modelIdentifier: String) -> Bool? {
        store.imageInputManualOverride(for: modelIdentifier)
    }

    mutating func setImageInputManualOverride(_ enabled: Bool?, for modelIdentifier: String) {
        store.setImageInputManualOverride(enabled, for: modelIdentifier)
    }

    func isImageInputSupportUnknown(for modelIdentifier: String) -> Bool {
        store.isImageInputSupportUnknown(
            for: modelIdentifier,
            apiBaseURL: chatSettings.apiURL
        )
    }

    func supportsImageInput(for modelIdentifier: String) -> Bool {
        store.supportsImageInput(
            for: modelIdentifier,
            apiBaseURL: chatSettings.apiURL
        )
    }

    func thinkingCapability(for modelIdentifier: String) -> ModelThinkingCapability? {
        let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let requestStyle = resolvedRequestStyle(for: chatSettings.apiURL)
        let provider = resolvedProvider(for: chatSettings.apiURL)
            ?? ModelCapabilityResolver.providerHint(from: requestStyle)
            ?? ChatAPIEndpointResolver.officialProviderHint(for: chatSettings.apiURL)
            ?? .openAICompatible
        return store.thinkingCapability(
            for: trimmed,
            apiBaseURL: chatSettings.apiURL,
            provider: provider,
            requestStyle: requestStyle
        )
    }

    func selectedThinkingOption(for modelIdentifier: String? = nil) -> ModelThinkingOption? {
        let model = (modelIdentifier ?? chatSettings.selectedModel).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, let capability = thinkingCapability(for: model) else { return nil }
        return store.selectedThinkingOption(
            for: model,
            apiBaseURL: chatSettings.apiURL,
            capability: capability
        )
    }

    mutating func setSelectedThinkingOption(_ option: ModelThinkingOption?, for modelIdentifier: String? = nil) -> Bool {
        let model = (modelIdentifier ?? chatSettings.selectedModel).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty,
              let capability = thinkingCapability(for: model) else {
            return false
        }
        store.setSelectedThinkingOption(
            option,
            for: model,
            apiBaseURL: chatSettings.apiURL,
            capability: capability
        )
        return true
    }

    mutating func toggleSelectedThinking(for modelIdentifier: String? = nil) -> Bool {
        let model = (modelIdentifier ?? chatSettings.selectedModel).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, let capability = thinkingCapability(for: model) else { return false }
        let next = capability.toggledSelection(from: selectedThinkingOption(for: model))
        return setSelectedThinkingOption(next, for: model)
    }

    private func manualChatAPIFormatPreference(for apiBaseURL: String) -> ChatAPIFormatPreference? {
        guard let presetID = selectedChatServerPresetID,
              let preset = chatServerPresets.first(where: { $0.id == presetID }) else {
            return nil
        }
        let selectedBase = ChatAPIEndpointResolver.normalizedAPIBaseKey(preset.apiURL)
        let requestedBase = ChatAPIEndpointResolver.normalizedAPIBaseKey(apiBaseURL)
        guard selectedBase != nil, selectedBase == requestedBase else { return nil }

        let preference = chatAPIFormatPreference(for: presetID)
        return preference == .automatic ? nil : preference
    }
}
