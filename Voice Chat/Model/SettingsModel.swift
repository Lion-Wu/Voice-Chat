//
//  SettingsModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation

struct ServerSettings: Codable {
    var serverAddress = "http://127.0.0.1:9880"
    var textLang = "auto"
    var refAudioPath = "Reference Audio/这种药水的易容效果确实很厉害，即便是美露莘也无法辨别出来。.wav"
    var promptText = "这种药水的易容效果确实很厉害，即便是美露莘也无法辨别出来。"
    var promptLang = "zh"
}

struct ModelSettings: Codable {
    var modelId = "1"
    var language = "auto"
    var autoSplit = "cut1"
}

struct ChatSettings: Codable {
    var apiURL = "http://localhost:11434"
    var selectedModel = ""
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var serverSettings: ServerSettings
    @Published var modelSettings: ModelSettings
    @Published var chatSettings: ChatSettings

    private init() {
        self.serverSettings = Self.loadServerSettings()
        self.modelSettings = Self.loadModelSettings()
        self.chatSettings = Self.loadChatSettings()
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

    func saveServerSettings() {
        Self.save(settings: serverSettings, forKey: "ServerSettings")
    }

    func saveModelSettings() {
        Self.save(settings: modelSettings, forKey: "ModelSettings")
    }

    func saveChatSettings() {
        Self.save(settings: chatSettings, forKey: "ChatSettings")
    }

    private static func save<T: Codable>(settings: T, forKey key: String) {
        if let data = try? PropertyListEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadServerSettings() -> ServerSettings {
        return load(forKey: "ServerSettings") ?? ServerSettings()
    }

    private static func loadModelSettings() -> ModelSettings {
        return load(forKey: "ModelSettings") ?? ModelSettings()
    }

    private static func loadChatSettings() -> ChatSettings {
        return load(forKey: "ChatSettings") ?? ChatSettings()
    }

    private static func load<T: Codable>(forKey key: String) -> T? {
        if let data = UserDefaults.standard.data(forKey: key),
           let settings = try? PropertyListDecoder().decode(T.self, from: data) {
            return settings
        }
        return nil
    }
}
