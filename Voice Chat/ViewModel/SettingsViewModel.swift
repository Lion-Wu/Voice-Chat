//
//  SettingsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.10.09.
//  Modified by [Your Name] on [Date]
//

import Foundation
import Combine

@MainActor
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
            // If enabling streaming, automatically set autoSplit to "cut0"
            if enableStreaming {
                autoSplit = "cut0"
            }
        }
    }
    @Published var autoSplit: String {
        didSet {
            saveModelSettings()
        }
    }
    @Published var modelId: String {
        didSet {
            saveModelSettings()
        }
    }
    @Published var language: String {
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
        self.modelId = modelSettings.modelId
        self.language = modelSettings.language
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
            modelId: modelId,
            language: language,
            autoSplit: autoSplit
        )
    }
}
