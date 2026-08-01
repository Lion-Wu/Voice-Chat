//
//  SettingsChatServerRuntime.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation
import SwiftData

@MainActor
enum SettingsChatServerRuntime {
    static func selectedPreset(
        in presets: [ChatServerPreset],
        selectedID: UUID?
    ) -> ChatServerPreset? {
        presets.first { $0.id == selectedID }
    }

    @discardableResult
    static func updateSettings(
        apiURL: String,
        selectedModel: String,
        chatSettings: inout ChatSettings,
        presets: [ChatServerPreset],
        selectedID: UUID?,
        hasContext: Bool,
        persistChatSettings: (ChatSettings) -> Void,
        save: (String) -> Void
    ) -> Bool {
        let nextSettings = ChatSettings(
            apiURL: apiURL,
            selectedModel: selectedModel,
            apiKey: chatSettings.apiKey
        )
        if nextSettings != chatSettings {
            chatSettings = nextSettings
            persistChatSettings(nextSettings)
        }

        guard hasContext else { return false }
        return ChatServerPresetStore.updateSelectedSettings(
            apiURL: apiURL,
            selectedModel: selectedModel,
            selectedID: selectedID,
            in: presets,
            save: save
        )
    }

    @discardableResult
    static func updateAPIKey(
        _ apiKey: String,
        chatSettings: inout ChatSettings,
        selectedID: UUID?,
        presets: [ChatServerPreset],
        hasContext: Bool,
        apiKeyStore: ChatAPIKeyStore,
        save: (String) -> Void
    ) -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != chatSettings.apiKey else { return false }
        chatSettings = ChatSettings(
            apiURL: chatSettings.apiURL,
            selectedModel: chatSettings.selectedModel,
            apiKey: trimmed
        )
        apiKeyStore.save(trimmed, for: selectedID)

        guard hasContext else { return false }
        return ChatServerPresetStore.touchAPIKey(
            selectedID: selectedID,
            in: presets,
            save: save
        )
    }

    static func createPreset(
        name: String,
        chatSettings: ChatSettings,
        apiFormatPreference: ChatAPIFormatPreference,
        apiKeyStore: ChatAPIKeyStore,
        context: ModelContext,
        save: (String) -> Void
    ) -> ChatServerPreset {
        SettingsPresetMutationController.createChatServerPreset(
            name: name,
            apiURL: chatSettings.apiURL,
            selectedModel: chatSettings.selectedModel,
            apiFormatPreference: apiFormatPreference,
            apiKey: chatSettings.apiKey,
            context: context,
            saveAPIKey: { apiKey, presetID in
                apiKeyStore.save(apiKey, for: presetID)
            },
            save: save
        )
    }

    static func deletePreset(
        id: UUID,
        presets: [ChatServerPreset],
        selectedID: inout UUID?,
        appSettings: AppSettings?,
        context: ModelContext,
        apiKeyStore: ChatAPIKeyStore,
        save: (String) -> Void
    ) -> Bool {
        SettingsPresetMutationController.deleteChatServerPreset(
            id: id,
            presets: presets,
            selectedID: &selectedID,
            appSettings: appSettings,
            context: context,
            deleteAPIKey: { presetID in
                apiKeyStore.delete(for: presetID)
            },
            save: save
        )
    }

    static func updatePreset(
        id: UUID,
        name: String?,
        apiFormatPreference: ChatAPIFormatPreference?,
        presets: [ChatServerPreset],
        save: (String) -> Void
    ) -> Bool {
        SettingsPresetMutationController.updateChatServerPreset(
            id: id,
            name: name,
            apiFormatPreference: apiFormatPreference,
            presets: presets,
            save: save
        )
    }

    static func selectPreset(
        id: UUID?,
        selectedID: inout UUID?,
        appSettings: AppSettings,
        presets: [ChatServerPreset],
        chatSettings: inout ChatSettings,
        apiKeyStore: ChatAPIKeyStore,
        persistChatSettings: (ChatSettings) -> Void,
        save: (String) -> Void
    ) -> Bool {
        guard selectedID != id else { return false }
        selectedID = id
        appSettings.selectedChatServerPresetID = id

        if let preset = selectedPreset(in: presets, selectedID: id) {
            let nextSettings = ChatSettings(
                apiURL: preset.apiURL,
                selectedModel: preset.selectedModel,
                apiKey: apiKeyStore.load(for: preset.id)
            )
            if nextSettings != chatSettings {
                chatSettings = nextSettings
                persistChatSettings(nextSettings)
            }
        }
        save("select chat server preset")
        return true
    }

    @discardableResult
    static func applySelectedPresetToChatSettings(
        presets: [ChatServerPreset],
        selectedID: UUID?,
        chatSettings: inout ChatSettings,
        apiKeyStore: ChatAPIKeyStore,
        persistChatSettings: (ChatSettings) -> Void
    ) -> Bool {
        guard let preset = selectedPreset(in: presets, selectedID: selectedID) else {
            return false
        }
        let nextSettings = ChatSettings(
            apiURL: preset.apiURL,
            selectedModel: preset.selectedModel,
            apiKey: apiKeyStore.load(for: preset.id)
        )
        guard nextSettings != chatSettings else { return false }
        chatSettings = nextSettings
        persistChatSettings(nextSettings)
        return true
    }
}
