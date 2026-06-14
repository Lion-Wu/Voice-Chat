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

    func saveSelectedVoiceServerPresetName() {
        guard !suppression.isActive(.saveVoiceServerPreset),
              selectedVoiceServerPresetID != nil else { return }
        presetBindingController.updateVoiceServerPresetName(voiceServerPresetName)
        reloadVoiceServerPresetListAndSelection()
    }

    func addVoiceServerPreset() {
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

    func saveSelectedChatServerPresetName() {
        guard !suppression.isActive(.saveChatServerPreset),
              selectedChatServerPresetID != nil else { return }
        presetBindingController.updateChatServerPresetName(chatServerPresetName)
        reloadChatServerPresetListAndSelection()
    }

    func saveSelectedChatServerPresetAPIFormatPreference() {
        guard !suppression.isActive(.saveChatServerPresetFormat),
              selectedChatServerPresetID != nil else { return }
        presetBindingController.updateChatServerAPIFormatPreference(selectedChatAPIFormatPreference)
        fetchAvailableModels()
    }

    func addChatServerPreset() {
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

    func savePresetFields() {
        guard !suppression.isActive(.saveVoicePreset), selectedPresetID != nil else { return }
        presetBindingController.updateVoicePreset(currentVoicePresetBinding())
        reloadPresetListAndSelection()
    }

    func addPreset() {
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

    func saveSelectedNormalSystemPromptPresetName() {
        guard !suppression.isActive(.saveNormalSystemPrompt),
              let id = selectedNormalSystemPromptPresetID else { return }
        presetBindingController.updateNormalSystemPromptPresetName(normalSystemPromptPresetName)
        if let idx = normalSystemPromptPresetList.firstIndex(where: { $0.id == id }) {
            normalSystemPromptPresetList[idx].name = normalSystemPromptPresetName
        }
    }

    func saveSelectedNormalSystemPromptPresetPrompt() {
        guard !suppression.isActive(.saveNormalSystemPrompt),
              selectedNormalSystemPromptPresetID != nil else { return }
        presetBindingController.updateNormalSystemPromptPresetPrompt(normalSystemPromptPrompt)
    }

    func saveSelectedVoiceSystemPromptPresetName() {
        guard !suppression.isActive(.saveVoiceSystemPrompt),
              let id = selectedVoiceSystemPromptPresetID else { return }
        presetBindingController.updateVoiceSystemPromptPresetName(voiceSystemPromptPresetName)
        if let idx = voiceSystemPromptPresetList.firstIndex(where: { $0.id == id }) {
            voiceSystemPromptPresetList[idx].name = voiceSystemPromptPresetName
        }
    }

    func saveSelectedVoiceSystemPromptPresetPrompt() {
        guard !suppression.isActive(.saveVoiceSystemPrompt),
              selectedVoiceSystemPromptPresetID != nil else { return }
        presetBindingController.updateVoiceSystemPromptPresetPrompt(voiceSystemPromptPrompt)
    }

    func addNormalSystemPromptPreset() {
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
