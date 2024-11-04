//
//  SettingsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.10.09.
//

import Foundation
import Combine

class SettingsViewModel: ObservableObject {
    @Published var serverAddress: String {
        didSet {
            saveServerSettings()
        }
    }
    @Published var textLang: String {
        didSet {
            saveServerSettings()
        }
    }
    @Published var refAudioPath: String {
        didSet {
            saveServerSettings()
        }
    }
    @Published var promptText: String {
        didSet {
            saveServerSettings()
        }
    }
    @Published var promptLang: String {
        didSet {
            saveServerSettings()
        }
    }

    @Published var apiURL: String {
        didSet {
            saveChatSettings()
        }
    }
    @Published var selectedModel: String {
        didSet {
            saveChatSettings()
        }
    }

    @Published var enableStreaming: Bool {
        didSet {
            saveVoiceSettings()
            if enableStreaming {
                autoSplit = "cut0" // This will trigger saveModelSettings()
            }
        }
    }
    @Published var autoSplit: String {
        didSet {
            saveModelSettings()
        }
    }

    private let settingsManager = SettingsManager.shared

    init() {
        let serverSettings = settingsManager.serverSettings
        self.serverAddress = serverSettings.serverAddress
        self.textLang = serverSettings.textLang
        self.refAudioPath = serverSettings.refAudioPath
        self.promptText = serverSettings.promptText
        self.promptLang = serverSettings.promptLang

        let chatSettings = settingsManager.chatSettings
        self.apiURL = chatSettings.apiURL
        self.selectedModel = chatSettings.selectedModel

        let voiceSettings = settingsManager.voiceSettings
        self.enableStreaming = voiceSettings.enableStreaming

        let modelSettings = settingsManager.modelSettings
        self.autoSplit = modelSettings.autoSplit
    }

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
            modelId: settingsManager.modelSettings.modelId,
            language: settingsManager.modelSettings.language,
            autoSplit: autoSplit
        )
    }
}
