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
        commitSelectedVoiceServerSettings(
            name: selectedVoiceServerPreset?.name ?? "",
            serverAddress: serverAddress,
            textLang: textLang
        )
    }

    func updateChatSettings(apiURL: String, selectedModel: String) {
        commitSelectedChatServerSettings(
            name: selectedChatServerPreset?.name ?? "",
            apiURL: apiURL,
            selectedModel: selectedModel,
            apiKey: chatSettings.apiKey,
            apiFormatPreference: chatModelCapabilities.selectedChatAPIFormatPreference()
        )
    }

    func updateChatAPIKey(_ apiKey: String) {
        commitSelectedChatServerSettings(
            name: selectedChatServerPreset?.name ?? "",
            apiURL: chatSettings.apiURL,
            selectedModel: chatSettings.selectedModel,
            apiKey: apiKey,
            apiFormatPreference: chatModelCapabilities.selectedChatAPIFormatPreference()
        )
    }

    /// Commits the complete selected voice-server draft as one transaction.
    /// Text fields stay local to the settings UI until this boundary is crossed.
    func commitSelectedVoiceServerSettings(
        name: String,
        serverAddress: String,
        textLang: String
    ) {
        let nextSettings = ServerSettings(serverAddress: serverAddress, textLang: textLang)
        let settingsChanged = nextSettings != serverSettings
        let selectedPreset = selectedVoiceServerPreset
        let presetChanged = selectedPreset.map {
            $0.name != name || $0.serverAddress != serverAddress
        } ?? false

        guard settingsChanged || presetChanged else { return }

        guard entity != nil, context != nil else {
            if settingsChanged {
                serverSettings = nextSettings
            }
            return
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
                onPersistentStoreReadFailure?(error)
                return
            }
        }
        if settingsChanged {
            serverSettings = nextSettings
        }
        if presetChanged {
            voiceServerPresets = voiceServerPresets.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    /// Commits URL, model, key and selected-preset metadata together. The AppSettings
    /// row and selected SwiftData preset share a single context save.
    func commitSelectedChatServerSettings(
        name: String,
        apiURL: String,
        selectedModel: String,
        apiKey: String,
        apiFormatPreference: ChatAPIFormatPreference
    ) {
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

        guard settingsChanged || presetChanged else { return }

        guard let entity, context != nil else {
            if settingsChanged {
                chatSettings = nextSettings
            }
            return
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
                print(SettingsCommitError.apiKeyWriteFailed.localizedDescription)
                return
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
                onPersistentStoreReadFailure?(error)
                return
            }
        }

        // Publish only after both persistent stores accepted the transaction.
        if settingsChanged {
            chatSettings = nextSettings
        }
        if presetChanged {
            chatServerPresets = chatServerPresets.sorted { $0.updatedAt > $1.updatedAt }
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
        voiceServerPresets = (voiceServerPresets + [preset]).sorted {
            $0.updatedAt > $1.updatedAt
        }
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
            voiceServerPresets.removeAll { $0.id == id }
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
            print(SettingsCommitError.apiKeyWriteFailed.localizedDescription)
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
            onPersistentStoreReadFailure?(error)
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

        let keyWriteResult = chatAPIKeyStore.write("", for: id)
        guard keyWriteResult != .failed else {
            persistence.rollbackPendingChanges()
            selectedChatServerPresetID = previousSelectedID
            print(SettingsCommitError.apiKeyWriteFailed.localizedDescription)
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
            onPersistentStoreReadFailure?(error)
            return
        }

        chatServerPresets.removeAll { $0.id == id }
        ensureSelectedChatServerPresetIsValid()
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
