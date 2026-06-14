//
//  SettingsManager+ServerPresets.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension SettingsManager {
    func updateServerSettings(serverAddress: String, textLang: String) {
        if SettingsVoiceServerRuntime.updateSettings(
            serverAddress: serverAddress,
            textLang: textLang,
            serverSettings: &serverSettings,
            presets: voiceServerPresets,
            selectedID: selectedVoiceServerPresetID,
            hasContext: context != nil,
            persistServerSettings: { [unowned self] settings in
                self.saveServerSettings(settings)
            },
            save: saveContext(label:)
        ) {
            loadVoiceServerPresetsFromStore()
        }
    }

    func updateChatSettings(apiURL: String, selectedModel: String) {
        if SettingsChatServerRuntime.updateSettings(
            apiURL: apiURL,
            selectedModel: selectedModel,
            chatSettings: &chatSettings,
            presets: chatServerPresets,
            selectedID: selectedChatServerPresetID,
            hasContext: context != nil,
            persistChatSettings: { [unowned self] settings in
                self.saveChatSettings(settings)
            },
            save: saveContext(label:)
        ) {
            loadChatServerPresetsFromStore()
        }
    }

    func updateChatAPIKey(_ apiKey: String) {
        if SettingsChatServerRuntime.updateAPIKey(
            apiKey,
            chatSettings: &chatSettings,
            selectedID: selectedChatServerPresetID,
            presets: chatServerPresets,
            hasContext: context != nil,
            apiKeyStore: chatAPIKeyStore,
            save: saveContext(label:)
        ) {
            loadChatServerPresetsFromStore()
        }
    }

    func createVoiceServerPreset(name: String = String(localized: "New Preset")) -> VoiceServerPreset? {
        guard let context else { return nil }
        let preset = SettingsVoiceServerRuntime.createPreset(
            name: name,
            serverSettings: serverSettings,
            context: context,
            save: saveContext(label:)
        )
        loadVoiceServerPresetsFromStore()
        return preset
    }

    func deleteVoiceServerPreset(_ id: UUID) {
        guard let context else { return }
        if SettingsVoiceServerRuntime.deletePreset(
            id: id,
            presets: voiceServerPresets,
            selectedID: &selectedVoiceServerPresetID,
            appSettings: entity,
            context: context,
            save: saveContext(label:)
        ) {
            loadVoiceServerPresetsFromStore()
            ensureSelectedVoiceServerPresetIsValid()
        }
    }

    func updateVoiceServerPreset(
        id: UUID,
        name: String? = nil
    ) {
        guard context != nil else { return }
        if SettingsVoiceServerRuntime.updatePreset(
            id: id,
            name: name,
            presets: voiceServerPresets,
            save: saveContext(label:)
        ) {
            loadVoiceServerPresetsFromStore()
        }
    }

    func selectVoiceServerPreset(_ id: UUID?) {
        guard context != nil, let e = entity else { return }
        _ = SettingsVoiceServerRuntime.selectPreset(
            id: id,
            selectedID: &selectedVoiceServerPresetID,
            appSettings: e,
            presets: voiceServerPresets,
            serverSettings: &serverSettings,
            persistServerSettings: { [unowned self] settings in
                self.saveServerSettings(settings)
            },
            save: saveContext(label:)
        )
    }

    func createChatServerPreset(name: String = String(localized: "New Preset")) -> ChatServerPreset? {
        guard let context else { return nil }
        let preset = SettingsChatServerRuntime.createPreset(
            name: name,
            chatSettings: chatSettings,
            apiFormatPreference: chatModelCapabilities.selectedChatAPIFormatPreference(),
            apiKeyStore: chatAPIKeyStore,
            context: context,
            save: saveContext(label:)
        )
        loadChatServerPresetsFromStore()
        return preset
    }

    func deleteChatServerPreset(_ id: UUID) {
        guard let context else { return }
        if SettingsChatServerRuntime.deletePreset(
            id: id,
            presets: chatServerPresets,
            selectedID: &selectedChatServerPresetID,
            appSettings: entity,
            context: context,
            apiKeyStore: chatAPIKeyStore,
            save: saveContext(label:)
        ) {
            loadChatServerPresetsFromStore()
            ensureSelectedChatServerPresetIsValid()
        }
    }

    func updateChatServerPreset(
        id: UUID,
        name: String? = nil,
        apiFormatPreference: ChatAPIFormatPreference? = nil
    ) {
        guard context != nil else { return }
        if SettingsChatServerRuntime.updatePreset(
            id: id,
            name: name,
            apiFormatPreference: apiFormatPreference,
            presets: chatServerPresets,
            save: saveContext(label:)
        ) {
            loadChatServerPresetsFromStore()
        }
    }

    func selectChatServerPreset(_ id: UUID?) {
        guard context != nil, let e = entity else { return }
        _ = SettingsChatServerRuntime.selectPreset(
            id: id,
            selectedID: &selectedChatServerPresetID,
            appSettings: e,
            presets: chatServerPresets,
            chatSettings: &chatSettings,
            apiKeyStore: chatAPIKeyStore,
            persistChatSettings: { [unowned self] settings in
                self.saveChatSettings(settings)
            },
            save: saveContext(label:)
        )
    }

    func applySelectedChatServerPresetToChatSettings() {
        SettingsChatServerRuntime.applySelectedPresetToChatSettings(
            presets: chatServerPresets,
            selectedID: selectedChatServerPresetID,
            chatSettings: &chatSettings,
            apiKeyStore: chatAPIKeyStore,
            persistChatSettings: { [unowned self] settings in
                self.saveChatSettings(settings)
            }
        )
    }

    func applySelectedVoiceServerPresetToServerSettings() {
        SettingsVoiceServerRuntime.applySelectedPresetToServerSettings(
            presets: voiceServerPresets,
            selectedID: selectedVoiceServerPresetID,
            serverSettings: &serverSettings,
            persistServerSettings: { [unowned self] settings in
                self.saveServerSettings(settings)
            }
        )
    }
}
