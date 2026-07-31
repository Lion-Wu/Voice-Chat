//
//  SettingsManager+PresetBootstrap.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension SettingsManager {
    func reloadAndRepairPresetStoresAfterAttach() throws {
        guard let context else { return }

        voiceServerPresets = try VoiceServerPresetStore.fetch(from: context)
        ensureDefaultVoiceServerPresetIfNeeded()
        ensureSelectedVoiceServerPresetIsValid()
        applySelectedVoiceServerPresetToServerSettings()

        chatServerPresets = try ChatServerPresetStore.fetch(from: context)
        ensureDefaultChatServerPresetIfNeeded()
        ensureSelectedChatServerPresetIsValid()
        applySelectedChatServerPresetToChatSettings()

        presets = try VoicePresetStore.fetch(from: context)
        ensureDefaultPresetIfNeeded()
        ensureSelectedPresetIsValid()

        systemPromptPresets = try SystemPromptPresetStore.fetch(from: context)
        ensureDefaultSystemPromptPresetsForModesIfNeeded()

        selectedPresetID = entity?.selectedPresetID ?? presets.first?.id
        selectedChatServerPresetID = entity?.selectedChatServerPresetID ?? chatServerPresets.first?.id
        selectedVoiceServerPresetID = entity?.selectedVoiceServerPresetID ?? voiceServerPresets.first?.id

        ensureSystemPromptSelectionsAreValid()
        selectedNormalSystemPromptPresetID = entity?.selectedNormalSystemPromptPresetID ?? selectedNormalSystemPromptPresetID
        selectedVoiceSystemPromptPresetID = entity?.selectedVoiceSystemPromptPresetID ?? selectedVoiceSystemPromptPresetID
    }

    func ensureDefaultChatServerPresetIfNeeded() {
        guard let context, let e = entity else { return }
        selectedChatServerPresetID = ChatServerPresetStore.ensureDefaultIfNeeded(
            presets: &chatServerPresets,
            appSettings: e,
            context: context,
            save: saveContext(label:)
        )
    }

    func ensureDefaultVoiceServerPresetIfNeeded() {
        guard let context, let e = entity else { return }
        selectedVoiceServerPresetID = VoiceServerPresetStore.ensureDefaultIfNeeded(
            presets: &voiceServerPresets,
            appSettings: e,
            context: context,
            save: saveContext(label:)
        )
    }

    func ensureSelectedChatServerPresetIsValid() {
        guard context != nil, let e = entity else { return }
        selectedChatServerPresetID = ChatServerPresetStore.validSelectionID(
            in: chatServerPresets,
            appSettings: e,
            save: saveContext(label:)
        )
    }

    func ensureSelectedVoiceServerPresetIsValid() {
        guard context != nil, let e = entity else { return }
        selectedVoiceServerPresetID = VoiceServerPresetStore.validSelectionID(
            in: voiceServerPresets,
            appSettings: e,
            save: saveContext(label:)
        )
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
