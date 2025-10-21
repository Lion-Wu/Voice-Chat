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
    // MARK: - Legacy fields (kept for backward compatibility)
    @Published var serverAddress: String { didSet { saveServerSettings() } }
    @Published var textLang: String { didSet { saveServerSettings() } }

    // These three legacy fields moved to preset management and remain only for compatibility.
    @Published var refAudioPath_legacy: String { didSet { saveServerSettings() } }
    @Published var promptText_legacy: String { didSet { saveServerSettings() } }
    @Published var promptLang_legacy: String { didSet { saveServerSettings() } }

    @Published var apiURL: String { didSet { saveChatSettings() } }
    @Published var selectedModel: String { didSet { saveChatSettings() } }

    @Published var enableStreaming: Bool {
        didSet {
            saveVoiceSettings()
            if enableStreaming {
                // Force "cut0" whenever streaming playback is enabled.
                autoSplit = "cut0"
            }
        }
    }
    @Published var autoReadAfterGeneration: Bool { didSet { saveVoiceSettings() } }

    @Published var autoSplit: String { didSet { saveModelSettings() } }
    @Published var modelId: String { didSet { saveModelSettings() } }
    @Published var language: String { didSet { saveModelSettings() } }

    // MARK: - Preset bindings
    struct PresetSummary: Identifiable, Equatable {
        var id: UUID
        var name: String
    }

    @Published var presetList: [PresetSummary] = []
    @Published var selectedPresetID: UUID? {
        didSet {
            if !suppressPresetDidSet {
                SettingsManager.shared.selectPreset(selectedPresetID, apply: true)
                // Reload the full preset details after switching selections.
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

    // MARK: - Dependency
    private let settingsManager = SettingsManager.shared

    // Avoid recursive didSet triggers when we change selection programmatically.
    private var suppressPresetDidSet = false
    private var suppressSavePreset = false

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
        autoReadAfterGeneration = v.autoReadAfterGeneration

        let m = settingsManager.modelSettings
        autoSplit = m.autoSplit
        modelId = m.modelId
        language = m.language

        reloadPresetListAndSelection()
        loadSelectedPresetFields()
    }

    // MARK: - Persistence (legacy settings)

    func saveServerSettings() {
        // Keep mirroring the legacy fields (ref/prompt_* remain for compatibility; TTS no longer reads them).
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
            enableStreaming: enableStreaming,
            autoReadAfterGeneration: autoReadAfterGeneration
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
        // The name might have changed; refresh the summary list.
        reloadPresetListAndSelection()
    }

    // MARK: - UI actions
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
}
