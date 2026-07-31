//
//  SettingsManager+ServerPresets.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

private enum SettingsCommitError: LocalizedError {
    case apiKeyWriteFailed

    var errorDescription: String? {
        switch self {
        case .apiKeyWriteFailed:
            return String(localized: "The API key could not be saved securely.")
        }
    }
}

extension SettingsManager {
    func updateServerSettings(serverAddress: String, textLang: String) {
        _ = commitSelectedVoiceServerSettings(
            name: selectedVoiceServerPreset?.name ?? "",
            serverAddress: serverAddress,
            textLang: textLang
        )
    }

    func updateChatSettings(apiURL: String, selectedModel: String) {
        _ = commitSelectedChatServerSettings(
            name: selectedChatServerPreset?.name ?? "",
            apiURL: apiURL,
            selectedModel: selectedModel,
            apiKey: chatSettings.apiKey,
            apiFormatPreference: chatModelCapabilities.selectedChatAPIFormatPreference()
        )
    }

    func updateChatAPIKey(_ apiKey: String) {
        _ = commitSelectedChatServerSettings(
            name: selectedChatServerPreset?.name ?? "",
            apiURL: chatSettings.apiURL,
            selectedModel: chatSettings.selectedModel,
            apiKey: apiKey,
            apiFormatPreference: chatModelCapabilities.selectedChatAPIFormatPreference()
        )
    }

    /// Commits the complete selected voice-server draft as one transaction.
    /// Text fields stay local to the settings UI until this boundary is crossed.
    @discardableResult
    func commitSelectedVoiceServerSettings(
        name: String,
        serverAddress: String,
        textLang: String
    ) -> Bool {
        let nextSettings = ServerSettings(serverAddress: serverAddress, textLang: textLang)
        let settingsChanged = nextSettings != serverSettings
        let selectedPreset = selectedVoiceServerPreset
        let presetChanged = selectedPreset.map {
            $0.name != name || $0.serverAddress != serverAddress
        } ?? false

        guard settingsChanged || presetChanged else { return true }

        guard entity != nil, context != nil else {
            if settingsChanged {
                serverSettings = nextSettings
            }
            return true
        }

        if presetChanged, let selectedPreset {
            selectedPreset.name = name
            selectedPreset.serverAddress = serverAddress
            selectedPreset.updatedAt = Date()
        }

        var persistentStateChanged = false
        if let entity {
            if entity.serverAddress != serverAddress {
                entity.serverAddress = serverAddress
                persistentStateChanged = true
            }
            if entity.textLang != textLang {
                entity.textLang = textLang
                persistentStateChanged = true
            }
            if presetChanged {
                persistentStateChanged = true
            }
        }

        if persistentStateChanged {
            do {
                try persistence.saveContextOrThrow(label: "commit voice server settings")
            } catch {
                persistence.rollbackPendingChanges()
                reportSettingsWriteFailure(error)
                return false
            }
        }
        if settingsChanged {
            serverSettings = nextSettings
        }
        if presetChanged {
            voiceServerPresets = voiceServerPresets.sorted { $0.updatedAt > $1.updatedAt }
        }
        return true
    }

    /// Commits URL, model, key and selected-preset metadata together. The AppSettings
    /// row and selected SwiftData preset share a single context save.
    @discardableResult
    func commitSelectedChatServerSettings(
        name: String,
        apiURL: String,
        selectedModel: String,
        apiKey: String,
        apiFormatPreference: ChatAPIFormatPreference
    ) -> Bool {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousSettings = chatSettings
        let nextSettings = ChatSettings(
            apiURL: apiURL,
            selectedModel: selectedModel,
            apiKey: trimmedAPIKey
        )
        let settingsChanged = nextSettings != previousSettings
        let keyChanged = trimmedAPIKey != previousSettings.apiKey
        let nextFormatRaw = apiFormatPreference == .automatic ? nil : apiFormatPreference.rawValue
        let selectedPreset = selectedChatServerPreset
        let presetChanged = selectedPreset.map {
            $0.name != name
                || $0.apiURL != apiURL
                || $0.selectedModel != selectedModel
                || $0.apiFormatPreferenceRaw != nextFormatRaw
                || keyChanged
        } ?? false

        guard settingsChanged || presetChanged else { return true }

        guard let entity, context != nil else {
            if settingsChanged {
                chatSettings = nextSettings
            }
            return true
        }

        let previousStoredAPIKey = keyChanged
            ? chatAPIKeyStore.load(for: selectedChatServerPresetID)
            : previousSettings.apiKey
        var keyWriteResult = ChatAPIKeyStore.WriteResult.unchanged
        if keyChanged {
            keyWriteResult = chatAPIKeyStore.write(
                trimmedAPIKey,
                for: selectedChatServerPresetID
            )
            guard keyWriteResult != .failed else {
                reportSettingsWriteFailure(SettingsCommitError.apiKeyWriteFailed)
                return false
            }
        }

        if presetChanged, let selectedPreset {
            selectedPreset.name = name
            selectedPreset.apiURL = apiURL
            selectedPreset.selectedModel = selectedModel
            selectedPreset.apiFormatPreferenceRaw = nextFormatRaw
            selectedPreset.updatedAt = Date()
        }

        var persistentStateChanged = false
        if entity.apiURL != apiURL {
            entity.apiURL = apiURL
            persistentStateChanged = true
        }
        if entity.selectedModel != selectedModel {
            entity.selectedModel = selectedModel
            persistentStateChanged = true
        }
        if presetChanged {
            persistentStateChanged = true
        }

        if persistentStateChanged {
            do {
                try persistence.saveContextOrThrow(label: "commit chat server settings")
            } catch {
                persistence.rollbackPendingChanges()
                if keyWriteResult == .updated,
                   chatAPIKeyStore.write(
                       previousStoredAPIKey,
                       for: selectedChatServerPresetID
                   ) == .failed {
                    print("Failed to restore the previous API key after a settings transaction error.")
                }
                reportSettingsWriteFailure(error)
                return false
            }
        }

        // Publish only after both persistent stores accepted the transaction.
        if settingsChanged {
            chatSettings = nextSettings
        }
        if presetChanged {
            chatServerPresets = chatServerPresets.sorted { $0.updatedAt > $1.updatedAt }
        }
        return true
    }

    func createVoiceServerPreset(name: String = String(localized: "New Preset")) -> VoiceServerPreset? {
        guard let context else { return nil }
        let preset = SettingsVoiceServerRuntime.createPreset(
            name: name,
            serverSettings: serverSettings,
            context: context,
            save: saveContext(label:)
        )
        voiceServerPresets = (voiceServerPresets + [preset]).sorted {
            $0.updatedAt > $1.updatedAt
        }
        return preset
    }

    func deleteVoiceServerPreset(_ id: UUID) {
        guard let context else { return }
        let previousSelectedID = selectedVoiceServerPresetID
        guard SettingsVoiceServerRuntime.deletePreset(
            id: id,
            presets: voiceServerPresets,
            selectedID: &selectedVoiceServerPresetID,
            appSettings: entity,
            context: context,
            save: { _ in }
        ) else { return }

        let remainingPresets = voiceServerPresets.filter { $0.id != id }
        var nextSettings = serverSettings
        if previousSelectedID == id, let entity {
            _ = SettingsVoiceServerRuntime.applySelectedPresetToServerSettings(
                presets: remainingPresets,
                selectedID: selectedVoiceServerPresetID,
                serverSettings: &nextSettings,
                persistServerSettings: { settings in
                    entity.serverAddress = settings.serverAddress
                    entity.textLang = settings.textLang
                }
            )
        }

        do {
            try persistence.saveContextOrThrow(label: "delete voice server preset")
        } catch {
            persistence.rollbackPendingChanges()
            selectedVoiceServerPresetID = previousSelectedID
            reportSettingsWriteFailure(error)
            return
        }

        voiceServerPresets = remainingPresets
        if nextSettings != serverSettings {
            serverSettings = nextSettings
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
            voiceServerPresets = voiceServerPresets.sorted { $0.updatedAt > $1.updatedAt }
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
            persistServerSettings: { settings in
                e.serverAddress = settings.serverAddress
                e.textLang = settings.textLang
            },
            save: saveContext(label:)
        )
    }

    func createChatServerPreset(name: String = String(localized: "New Preset")) -> ChatServerPreset? {
        guard let context else { return nil }
        let preset = ChatServerPresetStore.create(
            name: name,
            apiURL: chatSettings.apiURL,
            selectedModel: chatSettings.selectedModel,
            apiFormatPreference: chatModelCapabilities.selectedChatAPIFormatPreference(),
            context: context,
            save: { _ in }
        )

        let keyWriteResult: ChatAPIKeyStore.WriteResult
        if chatSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keyWriteResult = .unchanged
        } else {
            keyWriteResult = chatAPIKeyStore.write(chatSettings.apiKey, for: preset.id)
        }
        guard keyWriteResult != .failed else {
            persistence.rollbackPendingChanges()
            reportSettingsWriteFailure(SettingsCommitError.apiKeyWriteFailed)
            return nil
        }

        do {
            try persistence.saveContextOrThrow(label: "create chat server preset")
        } catch {
            persistence.rollbackPendingChanges()
            if keyWriteResult == .updated,
               chatAPIKeyStore.write("", for: preset.id) == .failed {
                print("Failed to remove an API key after preset creation was rolled back.")
            }
            reportSettingsWriteFailure(error)
            return nil
        }

        chatServerPresets = (chatServerPresets + [preset]).sorted {
            $0.updatedAt > $1.updatedAt
        }
        return preset
    }

    func deleteChatServerPreset(_ id: UUID) {
        guard let context else { return }
        let previousSelectedID = selectedChatServerPresetID
        let previousAPIKey = chatAPIKeyStore.load(for: id)
        guard ChatServerPresetStore.delete(
            id: id,
            from: chatServerPresets,
            selectedID: &selectedChatServerPresetID,
            appSettings: entity,
            context: context,
            save: { _ in }
        ) else { return }

        let remainingPresets = chatServerPresets.filter { $0.id != id }
        var nextSettings = chatSettings
        if previousSelectedID == id, let entity {
            _ = SettingsChatServerRuntime.applySelectedPresetToChatSettings(
                presets: remainingPresets,
                selectedID: selectedChatServerPresetID,
                chatSettings: &nextSettings,
                apiKeyStore: chatAPIKeyStore,
                persistChatSettings: { settings in
                    entity.apiURL = settings.apiURL
                    entity.selectedModel = settings.selectedModel
                }
            )
        }

        let keyWriteResult = chatAPIKeyStore.write("", for: id)
        guard keyWriteResult != .failed else {
            persistence.rollbackPendingChanges()
            selectedChatServerPresetID = previousSelectedID
            reportSettingsWriteFailure(SettingsCommitError.apiKeyWriteFailed)
            return
        }

        do {
            try persistence.saveContextOrThrow(label: "delete chat server preset")
        } catch {
            persistence.rollbackPendingChanges()
            selectedChatServerPresetID = previousSelectedID
            if keyWriteResult == .updated,
               chatAPIKeyStore.write(previousAPIKey, for: id) == .failed {
                print("Failed to restore an API key after preset deletion was rolled back.")
            }
            reportSettingsWriteFailure(error)
            return
        }

        chatServerPresets = remainingPresets
        if nextSettings != chatSettings {
            chatSettings = nextSettings
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
            chatServerPresets = chatServerPresets.sorted { $0.updatedAt > $1.updatedAt }
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
            persistChatSettings: { settings in
                e.apiURL = settings.apiURL
                e.selectedModel = settings.selectedModel
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
