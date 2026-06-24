//
//  SettingsManager+Persistence.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation
import SwiftData

extension SettingsManager {
    // SwiftData context injected from the app or root view.
    func attach(context: ModelContext) {
        guard let loaded = persistence.attach(
            context: context,
            chatAPIKeyForPreset: { [chatAPIKeyStore] in chatAPIKeyStore.load(for: $0) },
            defaultHapticFeedbackEnabled: SettingsDefaults.hapticFeedbackEnabled,
            defaultAPIAdvancedSettings: SettingsDefaults.apiAdvancedSettings
        ) else {
            return
        }

        applyLoadedState(loaded.loadedState)
        applyPendingStoredPreferences()
        reloadAndRepairPresetStoresAfterAttach()
    }

    func applyLoadedState(_ loadedState: AppSettingsLoadedState) {
        serverSettings = loadedState.serverSettings
        modelSettings = loadedState.modelSettings
        chatSettings = loadedState.chatSettings
        voiceSettings = loadedState.voiceSettings
        developerModeEnabled = loadedState.developerModeEnabled
        hapticFeedbackEnabled = loadedState.hapticFeedbackEnabled
        apiAdvancedSettings = loadedState.apiAdvancedSettings
        toolUseSettings = loadedState.toolUseSettings
        selectedVoiceServerPresetID = loadedState.selectedVoiceServerPresetID
        selectedChatServerPresetID = loadedState.selectedChatServerPresetID
        selectedPresetID = loadedState.selectedPresetID
        selectedNormalSystemPromptPresetID = loadedState.selectedNormalSystemPromptPresetID
        selectedVoiceSystemPromptPresetID = loadedState.selectedVoiceSystemPromptPresetID

        var capabilityStore = chatModelCapabilityStore
        capabilityStore.replaceImageInputOverrides(loadedState.modelImageInputOverrides)
        chatModelCapabilityStore = capabilityStore
    }

    func saveContext(label: String) {
        persistence.saveContext(label: label)
    }

    func saveChatModelImageInputOverrides() {
        guard let e = entity, context != nil else { return }
        e.modelImageInputOverrideJSON = ChatModelCapabilityStore.encodeImageInputOverrides(
            chatModelCapabilityStore.imageInputOverrides
        )
        saveContext(label: "save chat model image input overrides")
    }

    func updateModelSettings(modelId: String, language: String, autoSplit: String) {
        modelSettings.modelId = modelId
        modelSettings.language = language
        modelSettings.autoSplit = autoSplit
        saveModelSettings()
    }

    func updateVoiceSettings(enableStreaming: Bool) {
        voiceSettings.enableStreaming = enableStreaming
        saveVoiceSettings()
    }

    func updateDeveloperModeEnabled(_ enabled: Bool) {
        developerModeEnabled = enabled
        guard entity != nil, context != nil else {
            pendingDeveloperModeEnabled = enabled
            return
        }
        saveDeveloperModeEnabled()
    }

    func updateHapticFeedbackEnabled(_ enabled: Bool) {
        hapticFeedbackEnabled = enabled
        guard entity != nil, context != nil else {
            pendingHapticFeedbackEnabled = enabled
            return
        }
        saveHapticFeedbackEnabled()
    }

    func updateAPIAdvancedSettings(_ settings: APIAdvancedSettings) {
        apiAdvancedSettings = settings.sanitized
        guard entity != nil, context != nil else {
            pendingAPIAdvancedSettings = apiAdvancedSettings
            return
        }
        saveAPIAdvancedSettings()
    }

    func updateToolUseSettings(_ settings: ToolUseSettings) {
        toolUseSettings = settings
        guard entity != nil, context != nil else {
            pendingToolUseSettings = settings
            return
        }
        saveToolUseSettings()
    }

    func resetAPIAdvancedSettingsToDefaults() {
        updateAPIAdvancedSettings(SettingsDefaults.apiAdvancedSettings)
    }

    func saveServerSettings() {
        saveServerSettings(serverSettings)
    }

    func saveServerSettings(_ settings: ServerSettings) {
        guard let e = entity, context != nil else { return }
        e.serverAddress = settings.serverAddress
        e.textLang = settings.textLang
        saveContext(label: "save server settings")
    }

    func saveModelSettings() {
        guard let e = entity, context != nil else { return }
        e.modelId = modelSettings.modelId
        e.language = modelSettings.language
        e.autoSplit = modelSettings.autoSplit
        saveContext(label: "save model settings")
    }

    func saveChatSettings() {
        saveChatSettings(chatSettings)
    }

    func saveChatSettings(_ settings: ChatSettings) {
        guard let e = entity, context != nil else { return }
        e.apiURL = settings.apiURL
        e.selectedModel = settings.selectedModel
        saveContext(label: "save chat settings")
    }

    func saveVoiceSettings() {
        guard let e = entity, context != nil else { return }
        e.enableStreaming = voiceSettings.enableStreaming
        saveContext(label: "save voice settings")
    }

    func saveDeveloperModeEnabled() {
        guard let e = entity, context != nil else { return }
        e.developerModeEnabled = developerModeEnabled
        saveContext(label: "save developer mode")
    }

    func saveHapticFeedbackEnabled() {
        guard let e = entity, context != nil else { return }
        e.hapticFeedbackEnabled = hapticFeedbackEnabled
        saveContext(label: "save haptic feedback")
    }

    func saveAPIAdvancedSettings() {
        guard let e = entity, context != nil else { return }
        e.apiAdvancedSettingsJSON = APIAdvancedSettingsCodec.encode(apiAdvancedSettings)
        saveContext(label: "save API advanced settings")
    }

    func saveToolUseSettings() {
        guard let e = entity, context != nil else { return }
        e.toolUseSettingsJSON = ToolUseSettingsCodec.encode(toolUseSettings)
        saveContext(label: "save tool-use settings")
    }

    private func applyPendingStoredPreferences() {
        if let pending = pendingDeveloperModeEnabled {
            developerModeEnabled = pending
            entity?.developerModeEnabled = pending
            saveContext(label: "apply pending developer mode")
            pendingDeveloperModeEnabled = nil
        }

        if let pending = pendingHapticFeedbackEnabled {
            hapticFeedbackEnabled = pending
            entity?.hapticFeedbackEnabled = pending
            saveContext(label: "apply pending haptic feedback")
            pendingHapticFeedbackEnabled = nil
        }

        if let pending = pendingAPIAdvancedSettings {
            apiAdvancedSettings = pending.sanitized
            entity?.apiAdvancedSettingsJSON = APIAdvancedSettingsCodec.encode(apiAdvancedSettings)
            saveContext(label: "apply pending API advanced settings")
            pendingAPIAdvancedSettings = nil
        }

        if let pending = pendingToolUseSettings {
            toolUseSettings = pending
            entity?.toolUseSettingsJSON = ToolUseSettingsCodec.encode(pending)
            saveContext(label: "apply pending tool-use settings")
            pendingToolUseSettings = nil
        }
    }
}
