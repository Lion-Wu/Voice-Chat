//
//  ChatRuntimeConfigurationResolver.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

@MainActor
struct ChatRuntimeConfigurationResolver {
    private let settingsManager: SettingsManager

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    func currentConfiguration() -> ChatServiceConfiguration {
        let settings = settingsManager.chatSettings
        return ChatServiceConfiguration(
            apiBaseURL: settings.apiURL,
            modelIdentifier: settings.selectedModel,
            apiKey: settings.apiKey,
            providerHint: settingsManager.chatModelCapabilities.resolvedProvider(for: settings.apiURL),
            requestStyleHint: settingsManager.chatModelCapabilities.resolvedRequestStyle(for: settings.apiURL),
            thinkingCapability: settingsManager.chatModelCapabilities.thinkingCapability(for: settings.selectedModel),
            thinkingOption: settingsManager.chatModelCapabilities.selectedThinkingOption(for: settings.selectedModel),
            apiAdvancedSettings: settingsManager.activeAPIAdvancedSettings
        )
    }

    func supportsImageInput(fallbackModelIdentifier: String) -> Bool {
        settingsManager.chatModelCapabilities.supportsImageInput(
            for: effectiveModelIdentifier(fallback: fallbackModelIdentifier)
        )
    }

    func thinkingCapability(fallbackModelIdentifier: String) -> ModelThinkingCapability? {
        settingsManager.chatModelCapabilities.thinkingCapability(
            for: effectiveModelIdentifier(fallback: fallbackModelIdentifier)
        )
    }

    func selectedThinkingOption(fallbackModelIdentifier: String) -> ModelThinkingOption? {
        settingsManager.chatModelCapabilities.selectedThinkingOption(
            for: effectiveModelIdentifier(fallback: fallbackModelIdentifier)
        )
    }

    func setSelectedThinkingOption(_ option: ModelThinkingOption, fallbackModelIdentifier: String) {
        settingsManager.chatModelCapabilities.setSelectedThinkingOption(
            option,
            for: effectiveModelIdentifier(fallback: fallbackModelIdentifier)
        )
    }

    func toggleSelectedThinking(fallbackModelIdentifier: String) {
        settingsManager.chatModelCapabilities.toggleSelectedThinking(
            for: effectiveModelIdentifier(fallback: fallbackModelIdentifier)
        )
    }

    func developerPrompt(isVoiceMode: Bool) -> String? {
        let preset = isVoiceMode ? settingsManager.selectedVoiceSystemPromptPreset : settingsManager.selectedNormalSystemPromptPreset
        let raw = isVoiceMode ? preset?.voicePrompt : preset?.normalPrompt
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func effectiveModelIdentifier(fallback: String) -> String {
        let selected = settingsManager.chatSettings.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return selected.isEmpty ? fallback : selected
    }
}
