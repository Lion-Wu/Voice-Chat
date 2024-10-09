//
//  SettingsModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation

struct ServerSettings: Codable {
    var serverIP = "192.168.1.4"
    var port = "5000"
}

struct ModelSettings: Codable {
    var modelId = "1"
    var language = "auto"
    var autoSplit = "凑四句一切"
}

struct ChatSettings: Codable {
    var apiURL = "http://localhost:11434/v1"
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

    func updateServerSettings(serverIP: String, port: String) {
        serverSettings.serverIP = serverIP
        serverSettings.port = port
        saveServerSettings()
    }

    func updateModelSettings(modelId: String, language: String, autoSplit: String) {
        modelSettings.modelId = modelId
        modelSettings.language = language
        modelSettings.autoSplit = autoSplit
        saveModelSettings()
    }

    func updateChatSettings(apiURL: String) {
        chatSettings.apiURL = apiURL
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
        UserDefaults.standard.set(try? PropertyListEncoder().encode(settings), forKey: key)
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
        if let data = UserDefaults.standard.value(forKey: key) as? Data,
           let settings = try? PropertyListDecoder().decode(T.self, from: data) {
            return settings
        }
        return nil
    }
}
