//
//  SettingsModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation

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

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var serverSettings: ServerSettings
    @Published var modelSettings: ModelSettings
    @Published var chatSettings: ChatSettings
    @Published var voiceSettings: VoiceSettings

    private init() {
        self.serverSettings = Self.loadSettings(forKey: "ServerSettings") ?? ServerSettings(
            serverAddress: "http://127.0.0.1:9880",
            textLang: "auto",
            refAudioPath: "",
            promptText: "",
            promptLang: "auto"
        )
        self.modelSettings = Self.loadSettings(forKey: "ModelSettings") ?? ModelSettings(
            modelId: "",
            language: "auto",
            autoSplit: "cut0"
        )
        self.chatSettings = Self.loadSettings(forKey: "ChatSettings") ?? ChatSettings(
            apiURL: "http://localhost:1234",
            selectedModel: ""
        )
        self.voiceSettings = Self.loadSettings(forKey: "VoiceSettings") ?? VoiceSettings(enableStreaming: true)
    }

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

    func saveServerSettings() {
        Self.saveSettings(serverSettings, forKey: "ServerSettings")
    }

    func saveModelSettings() {
        Self.saveSettings(modelSettings, forKey: "ModelSettings")
    }

    func saveChatSettings() {
        Self.saveSettings(chatSettings, forKey: "ChatSettings")
    }

    func saveVoiceSettings() {
        Self.saveSettings(voiceSettings, forKey: "VoiceSettings")
    }

    private static func saveSettings<T: Codable>(_ settings: T, forKey key: String) {
        // 1) 在当前线程先把非 Sendable 的泛型 T 编码为 Data
        let encoded: Data?
        do {
            encoded = try PropertyListEncoder().encode(settings)
        } catch {
            print("Error encoding settings: \(error)")
            return
        }
        guard let finalData = encoded else { return }

        // 2) 把 Data 丢到后台写入 UserDefaults
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
