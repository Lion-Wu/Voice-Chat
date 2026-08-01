//
//  SettingsManager+SystemPromptPresets.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension SettingsManager {
    func createNormalSystemPromptPreset(name: String = String(localized: "New Prompt Preset")) -> SystemPromptPreset? {
        createSystemPromptPreset(mode: SystemPromptPresetStore.normalMode, name: name)
    }

    func createVoiceSystemPromptPreset(name: String = String(localized: "New Prompt Preset")) -> SystemPromptPreset? {
        createSystemPromptPreset(mode: SystemPromptPresetStore.voiceMode, name: name)
    }

    func deleteSystemPromptPreset(_ id: UUID) {
        guard let context else { return }
        if SettingsPresetMutationController.deleteSystemPromptPreset(
            id: id,
            presets: systemPromptPresets,
            context: context,
            save: saveContext(label:)
        ) {
            systemPromptPresets.removeAll { $0.id == id }
            ensureDefaultSystemPromptPresetsForModesIfNeeded()
            ensureSystemPromptSelectionsAreValid()
        }
    }

    func updateNormalSystemPromptPreset(
        id: UUID,
        name: String? = nil,
        prompt: String? = nil
    ) {
        guard context != nil else { return }
        if SettingsPresetMutationController.updateNormalSystemPromptPreset(
            id: id,
            name: name,
            prompt: prompt,
            presets: systemPromptPresets,
            save: saveContext(label:)
        ) {
            systemPromptPresets = systemPromptPresets.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func updateVoiceSystemPromptPreset(
        id: UUID,
        name: String? = nil,
        prompt: String? = nil
    ) {
        guard context != nil else { return }
        if SettingsPresetMutationController.updateVoiceSystemPromptPreset(
            id: id,
            name: name,
            prompt: prompt,
            presets: systemPromptPresets,
            save: saveContext(label:)
        ) {
            systemPromptPresets = systemPromptPresets.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func updateSystemPromptPreset(
        id: UUID,
        name: String? = nil,
        normalPrompt: String? = nil,
        voicePrompt: String? = nil
    ) {
        guard context != nil else { return }
        if SettingsPresetMutationController.updateSystemPromptPreset(
            id: id,
            name: name,
            normalPrompt: normalPrompt,
            voicePrompt: voicePrompt,
            presets: systemPromptPresets,
            save: saveContext(label:)
        ) {
            systemPromptPresets = systemPromptPresets.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func selectNormalSystemPromptPreset(_ id: UUID?) {
        guard context != nil, let e = entity else { return }
        _ = SettingsPresetMutationController.selectNormalSystemPromptPreset(
            id: id,
            selectedID: &selectedNormalSystemPromptPresetID,
            appSettings: e,
            save: saveContext(label:)
        )
    }

    func selectVoiceSystemPromptPreset(_ id: UUID?) {
        guard context != nil, let e = entity else { return }
        _ = SettingsPresetMutationController.selectVoiceSystemPromptPreset(
            id: id,
            selectedID: &selectedVoiceSystemPromptPresetID,
            appSettings: e,
            save: saveContext(label:)
        )
    }

    private func createSystemPromptPreset(mode: String, name: String) -> SystemPromptPreset? {
        guard let context else { return nil }
        let preset = SettingsPresetMutationController.createSystemPromptPreset(
            mode: mode,
            name: name,
            context: context,
            save: saveContext(label:)
        )
        systemPromptPresets = (systemPromptPresets + [preset]).sorted {
            $0.updatedAt > $1.updatedAt
        }
        return preset
    }
}
