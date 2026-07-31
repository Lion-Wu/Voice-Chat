//
//  SettingsViewModel+PresetBindings.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

@MainActor
extension SettingsViewModel {
    // MARK: - Voice server preset helpers

    func reloadVoiceServerPresetListAndSelection() {
        applyVoiceServerPresetBinding(presetBindingController.voiceServerBinding())
    }

    func loadSelectedVoiceServerPresetFields() {
        applyVoiceServerPresetBinding(presetBindingController.voiceServerBinding())
    }

    func addVoiceServerPreset() {
        commitVoiceServerEdits()
        if let id = presetBindingController.createVoiceServerPreset() {
            reloadVoiceServerPresetListAndSelection()
            presetBindingController.selectVoiceServerPreset(id)
            refreshFromSettingsManager()
            AppHaptics.trigger(.success)
        }
    }

    func deleteSelectedVoiceServerPreset() {
        guard selectedVoiceServerPresetID != nil else { return }
        presetBindingController.deleteSelectedVoiceServerPreset()
        refreshFromSettingsManager()
        AppHaptics.trigger(.warning)
    }

    // MARK: - Chat server preset helpers

    func reloadChatServerPresetListAndSelection() {
        applyChatServerPresetBinding(presetBindingController.chatServerBinding())
    }

    func loadSelectedChatServerPresetFields() {
        applyChatServerPresetBinding(presetBindingController.chatServerBinding())
    }

    func addChatServerPreset() {
        commitChatServerEdits()
        if let id = presetBindingController.createChatServerPreset() {
            reloadChatServerPresetListAndSelection()
            presetBindingController.selectChatServerPreset(id)
            refreshFromSettingsManager()
            AppHaptics.trigger(.success)
        }
    }

    func deleteSelectedChatServerPreset() {
        guard selectedChatServerPresetID != nil else { return }
        presetBindingController.deleteSelectedChatServerPreset()
        refreshFromSettingsManager()
        AppHaptics.trigger(.warning)
    }

    // MARK: - Voice preset helpers

    func reloadPresetListAndSelection() {
        applyVoicePresetBinding(presetBindingController.voicePresetBinding())
    }

    func loadSelectedPresetFields() {
        applyVoicePresetBinding(presetBindingController.voicePresetBinding())
    }

    func commitVoicePresetEdits() {
        guard !suppression.isActive(.saveVoicePreset),
              settingsManager.selectedPresetID != nil else { return }
        presetBindingController.updateVoicePreset(currentVoicePresetBinding())
        let presets = presetBindingController.voicePresetBinding().presets
        if presetList != presets {
            presetList = presets
        }
    }

    func addPreset() {
        commitVoicePresetEdits()
        if let id = presetBindingController.createVoicePreset() {
            reloadPresetListAndSelection()
            presetBindingController.selectVoicePreset(id, apply: false)
            reloadPresetListAndSelection()
            loadSelectedPresetFields()
            AppHaptics.trigger(.success)
        }
    }

    func deleteCurrentPreset() {
        guard selectedPresetID != nil else { return }
        presetBindingController.deleteSelectedVoicePreset()
        reloadPresetListAndSelection()
        loadSelectedPresetFields()
        AppHaptics.trigger(.warning)
    }

    func applySelectedPresetNow() {
        commitVoicePresetEdits()
        AppHaptics.trigger(.selection)
        Task { await settingsManager.applySelectedPreset() }
    }

    // MARK: - System prompt preset helpers

    func reloadSystemPromptPresetListsAndSelections() {
        applySystemPromptPresetBindings(presetBindingController.systemPromptBindings())
    }

    func loadSelectedNormalSystemPromptPresetFields() {
        applyNormalSystemPromptBinding(presetBindingController.normalSystemPromptBinding())
    }

    func loadSelectedVoiceSystemPromptPresetFields() {
        applyVoiceSystemPromptBinding(presetBindingController.voiceSystemPromptBinding())
    }

    func commitNormalSystemPromptEdits() {
        guard !suppression.isActive(.saveNormalSystemPrompt),
              let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.updateNormalSystemPromptPreset(
            id: id,
            name: normalSystemPromptPresetName,
            prompt: normalSystemPromptPrompt
        )
        let presets = presetBindingController.normalSystemPromptBinding().presets
        if normalSystemPromptPresetList != presets {
            normalSystemPromptPresetList = presets
        }
    }

    func commitVoiceSystemPromptEdits() {
        guard !suppression.isActive(.saveVoiceSystemPrompt),
              let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.updateVoiceSystemPromptPreset(
            id: id,
            name: voiceSystemPromptPresetName,
            prompt: voiceSystemPromptPrompt
        )
        let presets = presetBindingController.voiceSystemPromptBinding().presets
        if voiceSystemPromptPresetList != presets {
            voiceSystemPromptPresetList = presets
        }
    }

    func addNormalSystemPromptPreset() {
        commitNormalSystemPromptEdits()
        if let id = presetBindingController.createNormalSystemPromptPreset() {
            reloadSystemPromptPresetListsAndSelections()
            presetBindingController.selectNormalSystemPromptPreset(id)
            reloadSystemPromptPresetListsAndSelections()
            AppHaptics.trigger(.success)
        }
    }

    func deleteSelectedNormalSystemPromptPreset() {
        guard selectedNormalSystemPromptPresetID != nil else { return }
        presetBindingController.deleteSelectedNormalSystemPromptPreset()
        reloadSystemPromptPresetListsAndSelections()
        AppHaptics.trigger(.warning)
    }

    func addVoiceSystemPromptPreset() {
        commitVoiceSystemPromptEdits()
        if let id = presetBindingController.createVoiceSystemPromptPreset() {
            reloadSystemPromptPresetListsAndSelections()
            presetBindingController.selectVoiceSystemPromptPreset(id)
            reloadSystemPromptPresetListsAndSelections()
            AppHaptics.trigger(.success)
        }
    }

    func deleteSelectedVoiceSystemPromptPreset() {
        guard selectedVoiceSystemPromptPresetID != nil else { return }
        presetBindingController.deleteSelectedVoiceSystemPromptPreset()
        reloadSystemPromptPresetListsAndSelections()
        AppHaptics.trigger(.warning)
    }

    // MARK: - Binding application

    private func applyVoiceServerPresetBinding(_ binding: SettingsNamedPresetBinding) {
        voiceServerPresetList = binding.presets

        withSuppressed(.voiceServerPresetDidSet) {
            selectedVoiceServerPresetID = binding.selectedID
        }

        withSuppressed(.saveVoiceServerPreset) {
            voiceServerPresetName = binding.name
        }
    }

    private func applyChatServerPresetBinding(_ binding: SettingsChatServerPresetBinding) {
        chatServerPresetList = binding.presets

        withSuppressed(.chatServerPresetDidSet) {
            selectedChatServerPresetID = binding.selectedID
        }

        withSuppressed([
            .saveChatServerPreset,
            .saveChatServerPresetFormat
        ]) {
            chatServerPresetName = binding.name
            selectedChatAPIFormatPreference = binding.formatPreference
        }
    }

    private func applyVoicePresetBinding(_ binding: SettingsVoicePresetBinding) {
        presetList = binding.presets

        withSuppressed(.voicePresetDidSet) {
            selectedPresetID = binding.selectedID
        }

        withSuppressed(.saveVoicePreset) {
            presetName = binding.name
            presetRefAudioPath = binding.refAudioPath
            presetPromptText = binding.promptText
            presetPromptLang = binding.promptLang
            presetGPTWeightsPath = binding.gptWeightsPath
            presetSoVITSWeightsPath = binding.sovitsWeightsPath
        }
    }

    private func currentVoicePresetBinding() -> SettingsVoicePresetBinding {
        SettingsVoicePresetBinding(
            presets: presetList,
            selectedID: selectedPresetID,
            name: presetName,
            refAudioPath: presetRefAudioPath,
            promptText: presetPromptText,
            promptLang: presetPromptLang,
            gptWeightsPath: presetGPTWeightsPath,
            sovitsWeightsPath: presetSoVITSWeightsPath
        )
    }

    private func applySystemPromptPresetBindings(_ bindings: SettingsSystemPromptPresetBindings) {
        applyNormalSystemPromptBinding(bindings.normal)
        applyVoiceSystemPromptBinding(bindings.voice)
    }

    private func applyNormalSystemPromptBinding(_ binding: SettingsSystemPromptPresetBinding) {
        normalSystemPromptPresetList = binding.presets

        withSuppressed(.normalSystemPromptDidSet) {
            selectedNormalSystemPromptPresetID = binding.selectedID
        }

        withSuppressed(.saveNormalSystemPrompt) {
            normalSystemPromptPresetName = binding.name
            normalSystemPromptPrompt = binding.prompt
        }
    }

    private func applyVoiceSystemPromptBinding(_ binding: SettingsSystemPromptPresetBinding) {
        voiceSystemPromptPresetList = binding.presets

        withSuppressed(.voiceSystemPromptDidSet) {
            selectedVoiceSystemPromptPresetID = binding.selectedID
        }

        withSuppressed(.saveVoiceSystemPrompt) {
            voiceSystemPromptPresetName = binding.name
            voiceSystemPromptPrompt = binding.prompt
        }
    }
}
