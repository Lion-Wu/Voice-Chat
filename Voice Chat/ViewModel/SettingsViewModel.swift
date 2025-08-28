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
    // MARK: - Published Settings (双向绑定 -> 自动保存)
    @Published var serverAddress: String { didSet { saveServerSettings() } }
    @Published var textLang: String { didSet { saveServerSettings() } }
    @Published var refAudioPath: String { didSet { saveServerSettings() } }
    @Published var promptText: String { didSet { saveServerSettings() } }
    @Published var promptLang: String { didSet { saveServerSettings() } }

    @Published var apiURL: String { didSet { saveChatSettings() } }
    @Published var selectedModel: String { didSet { saveChatSettings() } }

    @Published var enableStreaming: Bool {
        didSet {
            saveVoiceSettings()
            if enableStreaming {
                // 开启流式时，强制切为 cut0
                autoSplit = "cut0"
            }
        }
    }

    @Published var autoSplit: String { didSet { saveModelSettings() } }
    @Published var modelId: String { didSet { saveModelSettings() } }
    @Published var language: String { didSet { saveModelSettings() } }

    // MARK: - Dependency
    private let settingsManager = SettingsManager.shared

    // MARK: - Init
    init() {
        let s = settingsManager.serverSettings
        serverAddress = s.serverAddress
        textLang = s.textLang
        refAudioPath = s.refAudioPath
        promptText = s.promptText
        promptLang = s.promptLang

        let c = settingsManager.chatSettings
        apiURL = c.apiURL
        selectedModel = c.selectedModel

        let v = settingsManager.voiceSettings
        enableStreaming = v.enableStreaming

        let m = settingsManager.modelSettings
        autoSplit = m.autoSplit
        modelId = m.modelId
        language = m.language
    }

    // MARK: - Persist
    func saveServerSettings() {
        settingsManager.updateServerSettings(
            serverAddress: serverAddress,
            textLang: textLang,
            refAudioPath: refAudioPath,
            promptText: promptText,
            promptLang: promptLang
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
}
