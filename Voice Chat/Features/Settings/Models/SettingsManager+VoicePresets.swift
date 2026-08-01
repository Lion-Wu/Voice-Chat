//
//  SettingsManager+VoicePresets.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension SettingsManager {
    func createPreset(name: String = String(localized: "New Preset")) -> VoicePreset? {
        guard let context else { return nil }
        let preset = SettingsPresetMutationController.createVoicePreset(
            name: name,
            promptLang: SettingsDefaults.promptLang,
            context: context,
            save: saveContext(label:)
        )
        presets = (presets + [preset]).sorted { $0.updatedAt > $1.updatedAt }
        return preset
    }

    func deletePreset(_ id: UUID) {
        guard let context else { return }
        if SettingsPresetMutationController.deleteVoicePreset(
            id: id,
            presets: presets,
            selectedID: &selectedPresetID,
            appSettings: entity,
            context: context,
            save: saveContext(label:)
        ) {
            presets.removeAll { $0.id == id }
        }
    }

    func updatePreset(
        id: UUID,
        name: String? = nil,
        refAudioPath: String? = nil,
        promptText: String? = nil,
        promptLang: String? = nil,
        gptWeightsPath: String? = nil,
        sovitsWeightsPath: String? = nil
    ) {
        guard context != nil else { return }
        if SettingsPresetMutationController.updateVoicePreset(
            id: id,
            name: name,
            refAudioPath: refAudioPath,
            promptText: promptText,
            promptLang: promptLang,
            gptWeightsPath: gptWeightsPath,
            sovitsWeightsPath: sovitsWeightsPath,
            presets: presets,
            save: saveContext(label:)
        ) {
            presets = presets.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func selectPreset(_ id: UUID?, apply: Bool = true) {
        guard context != nil, let e = entity else { return }
        guard SettingsPresetMutationController.selectVoicePreset(
            id: id,
            selectedID: &selectedPresetID,
            appSettings: e,
            save: saveContext(label:)
        ) else {
            return
        }
        if apply { Task { await self.applySelectedPreset() } }
    }

    func selectedPresetApplyRequest() -> TTSPresetApplyRequest? {
        guard let preset = selectedPreset else { return nil }
        return TTSPresetApplyRequest(
            serverAddress: serverSettings.serverAddress,
            gptWeightsPath: preset.gptWeightsPath,
            sovitsWeightsPath: preset.sovitsWeightsPath
        )
    }
}
