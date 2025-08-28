//
//  SettingsModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation

// MARK: - Value Types

struct ServerSettings: Codable {
    var serverAddress: String
    var textLang: String
    var refAudioPath: String
    var promptText: String
    var promptLang: String
}

struct ModelSettings: Codable {
    var modelId: String
    var language: String
    var autoSplit: String
}

struct ChatSettings: Codable {
    var apiURL: String
    var selectedModel: String
}

struct VoiceSettings: Codable {
    var enableStreaming: Bool
}

// MARK: - Settings Manager

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var serverSettings: ServerSettings
    @Published var modelSettings: ModelSettings
    @Published var chatSettings: ChatSettings
    @Published var voiceSettings: VoiceSettings

    // 避免魔法字符串
    private enum Keys {
        static let server = "ServerSettings"
        static let model  = "ModelSettings"
        static let chat   = "ChatSettings"
        static let voice  = "VoiceSettings"
    }

    private init() {
        self.serverSettings = Self.loadSettings(forKey: Keys.server) ?? ServerSettings(
            serverAddress: "http://127.0.0.1:9880",
            textLang: "auto",
            refAudioPath: "",
            promptText: "",
            promptLang: "auto"
        )
        self.modelSettings = Self.loadSettings(forKey: Keys.model) ?? ModelSettings(
            modelId: "",
            language: "auto",
            autoSplit: "cut0"
        )
        self.chatSettings = Self.loadSettings(forKey: Keys.chat) ?? ChatSettings(
            apiURL: "http://localhost:1234",
            selectedModel: ""
        )
        self.voiceSettings = Self.loadSettings(forKey: Keys.voice) ?? VoiceSettings(enableStreaming: true)
    }

    // MARK: - Update APIs

    func updateServerSettings(serverAddress: String, textLang: String, refAudioPath: String, promptText: String, promptLang: String) {
        serverSettings.serverAddress = serverAddress
        serverSettings.textLang = textLang
        serverSettings.refAudioPath = refAudioPath
        serverSettings.promptText = promptText
        serverSettings.promptLang = promptLang
        saveServerSettings()
    }

    func updateModelSettings(modelId: String, language: String, autoSplit: String) {
        modelSettings.modelId = modelId
        modelSettings.language = language
        modelSettings.autoSplit = autoSplit
        saveModelSettings()
    }

    func updateChatSettings(apiURL: String, selectedModel: String) {
        chatSettings.apiURL = apiURL
        chatSettings.selectedModel = selectedModel
        saveChatSettings()
    }

    func updateVoiceSettings(enableStreaming: Bool) {
        voiceSettings.enableStreaming = enableStreaming
        saveVoiceSettings()
    }

    // MARK: - Persist

    func saveServerSettings() {
        Self.saveSettings(serverSettings, forKey: Keys.server)
    }

    func saveModelSettings() {
        Self.saveSettings(modelSettings, forKey: Keys.model)
    }

    func saveChatSettings() {
        Self.saveSettings(chatSettings, forKey: Keys.chat)
    }

    func saveVoiceSettings() {
        Self.saveSettings(voiceSettings, forKey: Keys.voice)
    }

    private static func saveSettings<T: Codable>(_ settings: T, forKey key: String) {
        let encoded: Data?
        do {
            encoded = try PropertyListEncoder().encode(settings)
        } catch {
            print("Error encoding settings: \(error)")
            return
        }
        guard let finalData = encoded else { return }

        DispatchQueue.global(qos: .background).async {
            UserDefaults.standard.set(finalData, forKey: key)
        }
    }

    private static func loadSettings<T: Codable>(forKey key: String) -> T? {
        if let data = UserDefaults.standard.data(forKey: key),
           let settings = try? PropertyListDecoder().decode(T.self, from: data) {
            return settings
        }
        return nil
    }
}
