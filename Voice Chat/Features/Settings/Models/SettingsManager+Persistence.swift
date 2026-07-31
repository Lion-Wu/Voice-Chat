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
    @discardableResult
    func attach(context: ModelContext) -> Bool {
        do {
            guard let loaded = try persistence.attach(
                context: context,
                chatAPIKeyForPreset: { [chatAPIKeyStore] in chatAPIKeyStore.load(for: $0) },
                defaultHapticFeedbackEnabled: SettingsDefaults.hapticFeedbackEnabled,
                defaultAPIAdvancedSettings: SettingsDefaults.apiAdvancedSettings,
                deferSave: true
            ) else {
                return true
            }

            isCoalescingPersistenceWrites = true
            applyLoadedState(loaded.loadedState)
            applyPendingStoredPreferences()
            try reloadAndRepairPresetStoresAfterAttach()
            isCoalescingPersistenceWrites = false
            try persistence.saveContextOrThrow(label: "initialize settings stores")
            return true
        } catch {
            isCoalescingPersistenceWrites = false
            // Startup repair is one transaction. Discard inserts/deletes and
            // backfills staged before a later fetch or the final save failed,
            // so another subsystem cannot commit a partially initialized store.
            persistence.discardBinding()
            onPersistentStoreReadFailure?(error)
            return false
        }
    }

    func detachPersistentStore() {
        isCoalescingPersistenceWrites = false
        persistence.discardBinding()
        voiceServerPresets = []
        chatServerPresets = []
        presets = []
        systemPromptPresets = []
        selectedVoiceServerPresetID = nil
        selectedChatServerPresetID = nil
        selectedPresetID = nil
        selectedNormalSystemPromptPresetID = nil
        selectedVoiceSystemPromptPresetID = nil
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
        guard !isCoalescingPersistenceWrites else { return }
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
        let next = ModelSettings(modelId: modelId, language: language, autoSplit: autoSplit)
        guard next != modelSettings else { return }
        modelSettings = next
        saveModelSettings()
    }

    func updateVoiceSettings(
        enableStreaming: Bool,
        provider: TTSProvider,
        appleSpeechVoiceIdentifier: String?,
        personalVoiceIdentifier: String?
    ) {
        let next = VoiceSettings(
            enableStreaming: enableStreaming,
            provider: provider,
            appleSpeechVoiceIdentifier: appleSpeechVoiceIdentifier,
            personalVoiceIdentifier: personalVoiceIdentifier
        )
        guard next != voiceSettings else { return }
        voiceSettings = next
        saveVoiceSettings()
    }

    func updateDeveloperModeEnabled(_ enabled: Bool) {
        guard developerModeEnabled != enabled else { return }
        developerModeEnabled = enabled
        guard entity != nil, context != nil else {
            pendingDeveloperModeEnabled = enabled
            return
        }
        saveDeveloperModeEnabled()
    }

    func updateHapticFeedbackEnabled(_ enabled: Bool) {
        guard hapticFeedbackEnabled != enabled else { return }
        hapticFeedbackEnabled = enabled
        guard entity != nil, context != nil else {
            pendingHapticFeedbackEnabled = enabled
            return
        }
        saveHapticFeedbackEnabled()
    }

    func updateAPIAdvancedSettings(_ settings: APIAdvancedSettings) {
        let next = settings.sanitized
        guard next != apiAdvancedSettings else { return }
        apiAdvancedSettings = next
        guard entity != nil, context != nil else {
            pendingAPIAdvancedSettings = apiAdvancedSettings
            return
        }
        saveAPIAdvancedSettings()
    }

    func updateToolUseSettings(_ settings: ToolUseSettings) {
        guard settings != toolUseSettings else { return }
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

    func resetDeveloperSettingsToDefaults() {
        updateAPIAdvancedSettings(SettingsDefaults.apiAdvancedSettings)
        updateToolUseSettings(toolUseSettings.resettingDeveloperRequestPolicyToDefaults())
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
        e.ttsProviderRawValue = voiceSettings.provider.rawValue
        e.appleSpeechVoiceIdentifier = voiceSettings.appleSpeechVoiceIdentifier
        e.personalVoiceIdentifier = voiceSettings.personalVoiceIdentifier
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
