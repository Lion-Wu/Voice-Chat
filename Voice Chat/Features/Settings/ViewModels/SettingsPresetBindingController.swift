//
//  SettingsPresetBindingController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct SettingsPresetSummary: Identifiable, Equatable {
    var id: UUID
    var name: String
}

struct SettingsNamedPresetBinding: Equatable {
    var presets: [SettingsPresetSummary]
    var selectedID: UUID?
    var name: String
}

struct SettingsChatServerPresetBinding: Equatable {
    var presets: [SettingsPresetSummary]
    var selectedID: UUID?
    var name: String
    var formatPreference: ChatAPIFormatPreference
}

struct SettingsVoicePresetBinding: Equatable {
    var presets: [SettingsPresetSummary]
    var selectedID: UUID?
    var name: String
    var refAudioPath: String
    var promptText: String
    var promptLang: String
    var gptWeightsPath: String
    var sovitsWeightsPath: String
}

struct SettingsSystemPromptPresetBinding: Equatable {
    var presets: [SettingsPresetSummary]
    var selectedID: UUID?
    var name: String
    var prompt: String
}

struct SettingsSystemPromptPresetBindings: Equatable {
    var normal: SettingsSystemPromptPresetBinding
    var voice: SettingsSystemPromptPresetBinding
}

@MainActor
enum SettingsPresetBindingProjector {
    static func voiceServerBinding(
        presets: [VoiceServerPreset],
        selectedID: UUID?
    ) -> SettingsNamedPresetBinding {
        let selected = presets.first { $0.id == selectedID }
        return SettingsNamedPresetBinding(
            presets: summaries(from: presets),
            selectedID: selectedID,
            name: selected?.name ?? ""
        )
    }

    static func chatServerBinding(
        presets: [ChatServerPreset],
        selectedID: UUID?
    ) -> SettingsChatServerPresetBinding {
        let selected = presets.first { $0.id == selectedID }
        return SettingsChatServerPresetBinding(
            presets: summaries(from: presets),
            selectedID: selectedID,
            name: selected?.name ?? "",
            formatPreference: ChatServerPresetStore.apiFormatPreference(for: selectedID, in: presets)
        )
    }

    static func voicePresetBinding(
        presets: [VoicePreset],
        selectedID: UUID?
    ) -> SettingsVoicePresetBinding {
        guard let selected = presets.first(where: { $0.id == selectedID }) else {
            return SettingsVoicePresetBinding(
                presets: summaries(from: presets),
                selectedID: selectedID,
                name: "",
                refAudioPath: "",
                promptText: "",
                promptLang: "auto",
                gptWeightsPath: "",
                sovitsWeightsPath: ""
            )
        }

        return SettingsVoicePresetBinding(
            presets: summaries(from: presets),
            selectedID: selectedID,
            name: selected.name,
            refAudioPath: selected.refAudioPath,
            promptText: selected.promptText,
            promptLang: selected.promptLang,
            gptWeightsPath: selected.gptWeightsPath,
            sovitsWeightsPath: selected.sovitsWeightsPath
        )
    }

    static func systemPromptBindings(
        normalPresets: [SystemPromptPreset],
        selectedNormalID: UUID?,
        voicePresets: [SystemPromptPreset],
        selectedVoiceID: UUID?
    ) -> SettingsSystemPromptPresetBindings {
        SettingsSystemPromptPresetBindings(
            normal: normalSystemPromptBinding(
                presets: normalPresets,
                selectedID: selectedNormalID
            ),
            voice: voiceSystemPromptBinding(
                presets: voicePresets,
                selectedID: selectedVoiceID
            )
        )
    }

    static func normalSystemPromptBinding(
        presets: [SystemPromptPreset],
        selectedID: UUID?
    ) -> SettingsSystemPromptPresetBinding {
        let selected = presets.first { $0.id == selectedID }
        return SettingsSystemPromptPresetBinding(
            presets: summaries(from: presets),
            selectedID: selectedID,
            name: selected?.name ?? "",
            prompt: selected?.normalPrompt ?? ""
        )
    }

    static func voiceSystemPromptBinding(
        presets: [SystemPromptPreset],
        selectedID: UUID?
    ) -> SettingsSystemPromptPresetBinding {
        let selected = presets.first { $0.id == selectedID }
        return SettingsSystemPromptPresetBinding(
            presets: summaries(from: presets),
            selectedID: selectedID,
            name: selected?.name ?? "",
            prompt: selected?.voicePrompt ?? ""
        )
    }

    private static func summaries(from presets: [VoiceServerPreset]) -> [SettingsPresetSummary] {
        presets.map { SettingsPresetSummary(id: $0.id, name: $0.name) }
    }

    private static func summaries(from presets: [ChatServerPreset]) -> [SettingsPresetSummary] {
        presets.map { SettingsPresetSummary(id: $0.id, name: $0.name) }
    }

    private static func summaries(from presets: [VoicePreset]) -> [SettingsPresetSummary] {
        presets.map { SettingsPresetSummary(id: $0.id, name: $0.name) }
    }

    private static func summaries(from presets: [SystemPromptPreset]) -> [SettingsPresetSummary] {
        presets.map { SettingsPresetSummary(id: $0.id, name: $0.name) }
    }
}

@MainActor
struct SettingsPresetBindingController {
    private let settingsManager: SettingsManager

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    func voiceServerBinding() -> SettingsNamedPresetBinding {
        SettingsPresetBindingProjector.voiceServerBinding(
            presets: settingsManager.voiceServerPresets,
            selectedID: settingsManager.selectedVoiceServerPresetID
        )
    }

    func chatServerBinding() -> SettingsChatServerPresetBinding {
        SettingsPresetBindingProjector.chatServerBinding(
            presets: settingsManager.chatServerPresets,
            selectedID: settingsManager.selectedChatServerPresetID
        )
    }

    func voicePresetBinding() -> SettingsVoicePresetBinding {
        SettingsPresetBindingProjector.voicePresetBinding(
            presets: settingsManager.presets,
            selectedID: settingsManager.selectedPresetID
        )
    }

    func systemPromptBindings() -> SettingsSystemPromptPresetBindings {
        SettingsPresetBindingProjector.systemPromptBindings(
            normalPresets: settingsManager.normalSystemPromptPresets,
            selectedNormalID: settingsManager.selectedNormalSystemPromptPresetID,
            voicePresets: settingsManager.voiceSystemPromptPresets,
            selectedVoiceID: settingsManager.selectedVoiceSystemPromptPresetID
        )
    }

    func normalSystemPromptBinding() -> SettingsSystemPromptPresetBinding {
        SettingsPresetBindingProjector.normalSystemPromptBinding(
            presets: settingsManager.normalSystemPromptPresets,
            selectedID: settingsManager.selectedNormalSystemPromptPresetID
        )
    }

    func voiceSystemPromptBinding() -> SettingsSystemPromptPresetBinding {
        SettingsPresetBindingProjector.voiceSystemPromptBinding(
            presets: settingsManager.voiceSystemPromptPresets,
            selectedID: settingsManager.selectedVoiceSystemPromptPresetID
        )
    }

    func selectVoiceServerPreset(_ id: UUID?) {
        settingsManager.selectVoiceServerPreset(id)
    }

    func updateVoiceServerPresetName(_ name: String) {
        guard let id = settingsManager.selectedVoiceServerPresetID else { return }
        settingsManager.updateVoiceServerPreset(id: id, name: name)
    }

    func createVoiceServerPreset() -> UUID? {
        settingsManager.createVoiceServerPreset()?.id
    }

    func deleteSelectedVoiceServerPreset() {
        guard let id = settingsManager.selectedVoiceServerPresetID else { return }
        settingsManager.deleteVoiceServerPreset(id)
    }

    func selectChatServerPreset(_ id: UUID?) {
        settingsManager.selectChatServerPreset(id)
    }

    func updateChatServerPresetName(_ name: String) {
        guard let id = settingsManager.selectedChatServerPresetID else { return }
        settingsManager.updateChatServerPreset(id: id, name: name)
    }

    func updateChatServerAPIFormatPreference(_ preference: ChatAPIFormatPreference) {
        guard let id = settingsManager.selectedChatServerPresetID else { return }
        settingsManager.updateChatServerPreset(id: id, apiFormatPreference: preference)
    }

    func createChatServerPreset() -> UUID? {
        settingsManager.createChatServerPreset()?.id
    }

    func deleteSelectedChatServerPreset() {
        guard let id = settingsManager.selectedChatServerPresetID else { return }
        settingsManager.deleteChatServerPreset(id)
    }

    func selectVoicePreset(_ id: UUID?, apply: Bool) {
        settingsManager.selectPreset(id, apply: apply)
    }

    func updateVoicePreset(_ binding: SettingsVoicePresetBinding) {
        guard let id = settingsManager.selectedPresetID else { return }
        settingsManager.updatePreset(
            id: id,
            name: binding.name,
            refAudioPath: binding.refAudioPath,
            promptText: binding.promptText,
            promptLang: binding.promptLang,
            gptWeightsPath: binding.gptWeightsPath,
            sovitsWeightsPath: binding.sovitsWeightsPath
        )
    }

    func createVoicePreset() -> UUID? {
        settingsManager.createPreset()?.id
    }

    func deleteSelectedVoicePreset() {
        guard let id = settingsManager.selectedPresetID else { return }
        settingsManager.deletePreset(id)
    }

    func selectNormalSystemPromptPreset(_ id: UUID?) {
        settingsManager.selectNormalSystemPromptPreset(id)
    }

    func selectVoiceSystemPromptPreset(_ id: UUID?) {
        settingsManager.selectVoiceSystemPromptPreset(id)
    }

    func updateNormalSystemPromptPresetName(_ name: String) {
        guard let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.updateNormalSystemPromptPreset(id: id, name: name)
    }

    func updateNormalSystemPromptPresetPrompt(_ prompt: String) {
        guard let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.updateNormalSystemPromptPreset(id: id, prompt: prompt)
    }

    func updateVoiceSystemPromptPresetName(_ name: String) {
        guard let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.updateVoiceSystemPromptPreset(id: id, name: name)
    }

    func updateVoiceSystemPromptPresetPrompt(_ prompt: String) {
        guard let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.updateVoiceSystemPromptPreset(id: id, prompt: prompt)
    }

    func createNormalSystemPromptPreset() -> UUID? {
        settingsManager.createNormalSystemPromptPreset()?.id
    }

    func createVoiceSystemPromptPreset() -> UUID? {
        settingsManager.createVoiceSystemPromptPreset()?.id
    }

    func deleteSelectedNormalSystemPromptPreset() {
        guard let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.deleteSystemPromptPreset(id)
    }

    func deleteSelectedVoiceSystemPromptPreset() {
        guard let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.deleteSystemPromptPreset(id)
    }
}
