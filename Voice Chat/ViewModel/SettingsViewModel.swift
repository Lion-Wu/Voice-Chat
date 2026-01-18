//
//  SettingsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.10.09.
//

import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    // MARK: - Legacy settings
    @Published var serverAddress: String { didSet { saveServerSettings() } }
    @Published var textLang: String { didSet { saveServerSettings() } }

    // The following legacy fields now live on presets; we keep them for compatibility.
    @Published var refAudioPath_legacy: String { didSet { saveServerSettings() } }
    @Published var promptText_legacy: String { didSet { saveServerSettings() } }
    @Published var promptLang_legacy: String { didSet { saveServerSettings() } }

    @Published var apiURL: String { didSet { saveChatSettings() } }
    @Published var selectedModel: String { didSet { saveChatSettings() } }

    @Published var enableStreaming: Bool {
        didSet {
            saveVoiceSettings()
            if enableStreaming {
                // Force `cut0` when streaming is enabled.
                autoSplit = "cut0"
            }
        }
    }

    @Published var autoSplit: String { didSet { saveModelSettings() } }
    @Published var modelId: String { didSet { saveModelSettings() } }
    @Published var language: String { didSet { saveModelSettings() } }

    // MARK: - Preset bindings for the UI
    struct PresetSummary: Identifiable, Equatable {
        var id: UUID
        var name: String
    }

    @Published var presetList: [PresetSummary] = []
    @Published var selectedPresetID: UUID? {
        didSet {
            if !suppressPresetDidSet {
                SettingsManager.shared.selectPreset(selectedPresetID, apply: true)
                // Reload the preset fields after switching selection.
                loadSelectedPresetFields()
            }
        }
    }

    @Published var presetName: String = ""          { didSet { savePresetFields() } }
    @Published var presetRefAudioPath: String = ""  { didSet { savePresetFields() } }
    @Published var presetPromptText: String = ""    { didSet { savePresetFields() } }
    @Published var presetPromptLang: String = "auto" { didSet { savePresetFields() } }
    @Published var presetGPTWeightsPath: String = "" { didSet { savePresetFields() } }
    @Published var presetSoVITSWeightsPath: String = "" { didSet { savePresetFields() } }

    // MARK: - System prompt presets (normal / voice are separate)

    @Published var normalSystemPromptPresetList: [PresetSummary] = []
    @Published var selectedNormalSystemPromptPresetID: UUID? {
        didSet {
            if !suppressNormalSystemPromptDidSet {
                SettingsManager.shared.selectNormalSystemPromptPreset(selectedNormalSystemPromptPresetID)
                loadSelectedNormalSystemPromptPresetFields()
            }
        }
    }
    @Published var normalSystemPromptPresetName: String = "" { didSet { saveSelectedNormalSystemPromptPresetName() } }
    @Published var normalSystemPromptPrompt: String = "" { didSet { saveSelectedNormalSystemPromptPresetPrompt() } }

    @Published var voiceSystemPromptPresetList: [PresetSummary] = []
    @Published var selectedVoiceSystemPromptPresetID: UUID? {
        didSet {
            if !suppressVoiceSystemPromptDidSet {
                SettingsManager.shared.selectVoiceSystemPromptPreset(selectedVoiceSystemPromptPresetID)
                loadSelectedVoiceSystemPromptPresetFields()
            }
        }
    }
    @Published var voiceSystemPromptPresetName: String = "" { didSet { saveSelectedVoiceSystemPromptPresetName() } }
    @Published var voiceSystemPromptPrompt: String = "" { didSet { saveSelectedVoiceSystemPromptPresetPrompt() } }

    // MARK: - Dependency
    private let settingsManager = SettingsManager.shared

    // Avoid recursive didSet triggers when swapping presets.
    private var suppressPresetDidSet = false
    private var suppressSavePreset = false

    private var suppressNormalSystemPromptDidSet = false
    private var suppressSaveNormalSystemPrompt = false
    private var suppressVoiceSystemPromptDidSet = false
    private var suppressSaveVoiceSystemPrompt = false

    // MARK: - Init
    init() {
        let s = settingsManager.serverSettings
        serverAddress = s.serverAddress
        textLang = s.textLang
        refAudioPath_legacy = s.refAudioPath
        promptText_legacy = s.promptText
        promptLang_legacy = s.promptLang

        let c = settingsManager.chatSettings
        apiURL = c.apiURL
        selectedModel = c.selectedModel

        let v = settingsManager.voiceSettings
        enableStreaming = v.enableStreaming

        let m = settingsManager.modelSettings
        autoSplit = m.autoSplit
        modelId = m.modelId
        language = m.language

        reloadPresetListAndSelection()
        loadSelectedPresetFields()

        reloadSystemPromptPresetListsAndSelections()
    }

    // MARK: - Persist legacy settings

    func saveServerSettings() {
        // Write back the legacy fields so any older callers stay in sync.
        settingsManager.updateServerSettings(
            serverAddress: serverAddress,
            textLang: textLang,
            refAudioPath: refAudioPath_legacy,
            promptText: promptText_legacy,
            promptLang: promptLang_legacy
        )
    }

    func saveChatSettings() {
        settingsManager.updateChatSettings(
            apiURL: apiURL,
            selectedModel: selectedModel
        )
    }

    func saveVoiceSettings() {
        settingsManager.updateVoiceSettings(
            enableStreaming: enableStreaming
        )
    }

    func saveModelSettings() {
        settingsManager.updateModelSettings(
            modelId: modelId,
            language: language,
            autoSplit: autoSplit
        )
    }

    // MARK: - Preset helpers

    func reloadPresetListAndSelection() {
        presetList = settingsManager.presets.map { .init(id: $0.id, name: $0.name) }
        suppressPresetDidSet = true
        selectedPresetID = settingsManager.selectedPresetID
        suppressPresetDidSet = false
    }

    func loadSelectedPresetFields() {
        guard let id = settingsManager.selectedPresetID,
              let p = settingsManager.presets.first(where: { $0.id == id }) else {
            presetName = ""
            presetRefAudioPath = ""
            presetPromptText = ""
            presetPromptLang = "auto"
            presetGPTWeightsPath = ""
            presetSoVITSWeightsPath = ""
            return
        }
        suppressSavePreset = true
        presetName = p.name
        presetRefAudioPath = p.refAudioPath
        presetPromptText = p.promptText
        presetPromptLang = p.promptLang
        presetGPTWeightsPath = p.gptWeightsPath
        presetSoVITSWeightsPath = p.sovitsWeightsPath
        suppressSavePreset = false
    }

    private func savePresetFields() {
        guard !suppressSavePreset, let id = settingsManager.selectedPresetID else { return }
        settingsManager.updatePreset(
            id: id,
            name: presetName,
            refAudioPath: presetRefAudioPath,
            promptText: presetPromptText,
            promptLang: presetPromptLang,
            gptWeightsPath: presetGPTWeightsPath,
            sovitsWeightsPath: presetSoVITSWeightsPath
        )
        // Refresh the list because the preset name may have changed.
        reloadPresetListAndSelection()
    }

    // MARK: - UI operations
    func addPreset() {
        if let p = settingsManager.createPreset() {
            reloadPresetListAndSelection()
            settingsManager.selectPreset(p.id, apply: false)
            reloadPresetListAndSelection()
            loadSelectedPresetFields()
        }
    }

    func deleteCurrentPreset() {
        guard let id = settingsManager.selectedPresetID else { return }
        settingsManager.deletePreset(id)
        reloadPresetListAndSelection()
        loadSelectedPresetFields()
    }

    func applySelectedPresetNow() {
        Task { await settingsManager.applySelectedPreset() }
    }

    // MARK: - System prompt preset helpers

    func reloadSystemPromptPresetListsAndSelections() {
        normalSystemPromptPresetList = settingsManager.normalSystemPromptPresets.map { .init(id: $0.id, name: $0.name) }
        voiceSystemPromptPresetList = settingsManager.voiceSystemPromptPresets.map { .init(id: $0.id, name: $0.name) }

        suppressNormalSystemPromptDidSet = true
        selectedNormalSystemPromptPresetID = settingsManager.selectedNormalSystemPromptPresetID
        suppressNormalSystemPromptDidSet = false
        loadSelectedNormalSystemPromptPresetFields()

        suppressVoiceSystemPromptDidSet = true
        selectedVoiceSystemPromptPresetID = settingsManager.selectedVoiceSystemPromptPresetID
        suppressVoiceSystemPromptDidSet = false
        loadSelectedVoiceSystemPromptPresetFields()
    }

    func loadSelectedNormalSystemPromptPresetFields() {
        guard let id = settingsManager.selectedNormalSystemPromptPresetID,
              let p = settingsManager.normalSystemPromptPresets.first(where: { $0.id == id }) else {
            normalSystemPromptPresetName = ""
            normalSystemPromptPrompt = ""
            return
        }
        suppressSaveNormalSystemPrompt = true
        normalSystemPromptPresetName = p.name
        normalSystemPromptPrompt = p.normalPrompt
        suppressSaveNormalSystemPrompt = false
    }

    func loadSelectedVoiceSystemPromptPresetFields() {
        guard let id = settingsManager.selectedVoiceSystemPromptPresetID,
              let p = settingsManager.voiceSystemPromptPresets.first(where: { $0.id == id }) else {
            voiceSystemPromptPresetName = ""
            voiceSystemPromptPrompt = ""
            return
        }
        suppressSaveVoiceSystemPrompt = true
        voiceSystemPromptPresetName = p.name
        voiceSystemPromptPrompt = p.voicePrompt
        suppressSaveVoiceSystemPrompt = false
    }

    private func saveSelectedNormalSystemPromptPresetName() {
        guard !suppressSaveNormalSystemPrompt,
              let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.updateNormalSystemPromptPreset(id: id, name: normalSystemPromptPresetName)
        if let idx = normalSystemPromptPresetList.firstIndex(where: { $0.id == id }) {
            normalSystemPromptPresetList[idx].name = normalSystemPromptPresetName
        }
    }

    private func saveSelectedNormalSystemPromptPresetPrompt() {
        guard !suppressSaveNormalSystemPrompt,
              let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.updateNormalSystemPromptPreset(id: id, prompt: normalSystemPromptPrompt)
    }

    private func saveSelectedVoiceSystemPromptPresetName() {
        guard !suppressSaveVoiceSystemPrompt,
              let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.updateVoiceSystemPromptPreset(id: id, name: voiceSystemPromptPresetName)
        if let idx = voiceSystemPromptPresetList.firstIndex(where: { $0.id == id }) {
            voiceSystemPromptPresetList[idx].name = voiceSystemPromptPresetName
        }
    }

    private func saveSelectedVoiceSystemPromptPresetPrompt() {
        guard !suppressSaveVoiceSystemPrompt,
              let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.updateVoiceSystemPromptPreset(id: id, prompt: voiceSystemPromptPrompt)
    }

    func addNormalSystemPromptPreset() {
        if let p = settingsManager.createNormalSystemPromptPreset() {
            reloadSystemPromptPresetListsAndSelections()
            SettingsManager.shared.selectNormalSystemPromptPreset(p.id)
            reloadSystemPromptPresetListsAndSelections()
        }
    }

    func deleteSelectedNormalSystemPromptPreset() {
        guard let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.deleteSystemPromptPreset(id)
        reloadSystemPromptPresetListsAndSelections()
    }

    func addVoiceSystemPromptPreset() {
        if let p = settingsManager.createVoiceSystemPromptPreset() {
            reloadSystemPromptPresetListsAndSelections()
            SettingsManager.shared.selectVoiceSystemPromptPreset(p.id)
            reloadSystemPromptPresetListsAndSelections()
        }
    }

    func deleteSelectedVoiceSystemPromptPreset() {
        guard let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.deleteSystemPromptPreset(id)
        reloadSystemPromptPresetListsAndSelections()
    }
}
