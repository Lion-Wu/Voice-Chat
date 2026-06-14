//
//  SettingsManager+PresetBootstrap.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension SettingsManager {
    func reloadAndRepairPresetStoresAfterAttach() {
        loadVoiceServerPresetsFromStore()
        ensureDefaultVoiceServerPresetIfNeeded()
        ensureSelectedVoiceServerPresetIsValid()

        loadChatServerPresetsFromStore()
        ensureDefaultChatServerPresetIfNeeded()
        ensureSelectedChatServerPresetIsValid()

        loadPresetsFromStore()
        ensureDefaultPresetIfNeeded()
        ensureSelectedPresetIsValid()

        loadSystemPromptPresetsFromStore()
        ensureDefaultSystemPromptPresetsForModesIfNeeded()

        selectedPresetID = entity?.selectedPresetID ?? presets.first?.id
        selectedChatServerPresetID = entity?.selectedChatServerPresetID ?? chatServerPresets.first?.id
        selectedVoiceServerPresetID = entity?.selectedVoiceServerPresetID ?? voiceServerPresets.first?.id

        ensureSystemPromptSelectionsAreValid()
        selectedNormalSystemPromptPresetID = entity?.selectedNormalSystemPromptPresetID ?? selectedNormalSystemPromptPresetID
        selectedVoiceSystemPromptPresetID = entity?.selectedVoiceSystemPromptPresetID ?? selectedVoiceSystemPromptPresetID
    }

    func loadChatServerPresetsFromStore() {
        guard let context else { return }
        chatServerPresets = ChatServerPresetStore.fetch(from: context)
    }

    func loadVoiceServerPresetsFromStore() {
        guard let context else { return }
        voiceServerPresets = VoiceServerPresetStore.fetch(from: context)
    }

    func loadPresetsFromStore() {
        guard let context else { return }
        presets = VoicePresetStore.fetch(from: context)
    }

    func loadSystemPromptPresetsFromStore() {
        guard let context else { return }
        systemPromptPresets = SystemPromptPresetStore.fetch(from: context)
    }

    func ensureDefaultChatServerPresetIfNeeded() {
        guard let context, let e = entity else { return }
        selectedChatServerPresetID = ChatServerPresetStore.ensureDefaultIfNeeded(
            presets: &chatServerPresets,
            appSettings: e,
            context: context,
            save: saveContext(label:)
        )
        applySelectedChatServerPresetToChatSettings()
    }

    func ensureDefaultVoiceServerPresetIfNeeded() {
        guard let context, let e = entity else { return }
        selectedVoiceServerPresetID = VoiceServerPresetStore.ensureDefaultIfNeeded(
            presets: &voiceServerPresets,
            appSettings: e,
            context: context,
            save: saveContext(label:)
        )
        applySelectedVoiceServerPresetToServerSettings()
    }

    func ensureSelectedChatServerPresetIsValid() {
        guard context != nil, let e = entity else { return }
        selectedChatServerPresetID = ChatServerPresetStore.validSelectionID(
            in: chatServerPresets,
            appSettings: e,
            save: saveContext(label:)
        )
        applySelectedChatServerPresetToChatSettings()
    }

    func ensureSelectedVoiceServerPresetIsValid() {
        guard context != nil, let e = entity else { return }
        selectedVoiceServerPresetID = VoiceServerPresetStore.validSelectionID(
            in: voiceServerPresets,
            appSettings: e,
            save: saveContext(label:)
        )
        applySelectedVoiceServerPresetToServerSettings()
    }

    func ensureDefaultPresetIfNeeded() {
        guard let context, let e = entity else { return }
        selectedPresetID = VoicePresetStore.ensureDefaultIfNeeded(
            presets: &presets,
            appSettings: e,
            promptLang: SettingsDefaults.promptLang,
            context: context,
            save: saveContext(label:)
        )
    }

    func ensureSelectedPresetIsValid() {
        guard context != nil, let e = entity else { return }
        selectedPresetID = VoicePresetStore.validSelectionID(
            in: presets,
            appSettings: e,
            save: saveContext(label:)
        )
    }

    func ensureDefaultSystemPromptPresetsForModesIfNeeded() {
        guard let context else { return }
        SystemPromptPresetStore.ensureDefaultsIfNeeded(
            presets: &systemPromptPresets,
            context: context,
            save: saveContext(label:)
        )
    }

    func ensureSystemPromptSelectionsAreValid() {
        guard context != nil, let e = entity else { return }
        guard let repair = SystemPromptPresetStore.repairedSelection(
            in: systemPromptPresets,
            selectedNormalID: selectedNormalSystemPromptPresetID,
            persistedNormalID: e.selectedNormalSystemPromptPresetID,
            selectedVoiceID: selectedVoiceSystemPromptPresetID,
            persistedVoiceID: e.selectedVoiceSystemPromptPresetID
        ) else {
            return
        }

        selectedNormalSystemPromptPresetID = repair.normalID
        selectedVoiceSystemPromptPresetID = repair.voiceID
        e.selectedNormalSystemPromptPresetID = repair.normalID
        e.selectedVoiceSystemPromptPresetID = repair.voiceID

        if repair.didRepairPersistedSelection {
            saveContext(label: "repair system prompt selections")
        }
    }
}
