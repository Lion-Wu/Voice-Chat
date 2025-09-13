//
//  SettingsModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation
import SwiftData

// MARK: - Value Types（与 UI 交互的轻量结构体）

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

// MARK: - SwiftData 实体（单行表：保存所有设置）

@Model
final class AppSettings {
    var id: UUID
    var serverAddress: String
    var textLang: String
    var refAudioPath: String
    var promptText: String
    var promptLang: String

    var modelId: String
    var language: String
    var autoSplit: String

    var apiURL: String
    var selectedModel: String

    var enableStreaming: Bool

    init(
        serverAddress: String = "http://127.0.0.1:9880",
        textLang: String = "auto",
        refAudioPath: String = "",
        promptText: String = "",
        promptLang: String = "auto",
        modelId: String = "",
        language: String = "auto",
        autoSplit: String = "cut0",
        apiURL: String = "http://localhost:1234",
        selectedModel: String = "",
        enableStreaming: Bool = true
    ) {
        self.id = UUID()
        self.serverAddress = serverAddress
        self.textLang = textLang
        self.refAudioPath = refAudioPath
        self.promptText = promptText
        self.promptLang = promptLang
        self.modelId = modelId
        self.language = language
        self.autoSplit = autoSplit
        self.apiURL = apiURL
        self.selectedModel = selectedModel
        self.enableStreaming = enableStreaming
    }
}

// MARK: - Settings Manager（从 UserDefaults 改为 SwiftData）

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var serverSettings: ServerSettings
    @Published var modelSettings: ModelSettings
    @Published var chatSettings: ChatSettings
    @Published var voiceSettings: VoiceSettings

    private var context: ModelContext?
    private var entity: AppSettings?

    private init() {
        // 先用默认值，等 attach(context:) 后加载数据库
        self.serverSettings = ServerSettings(
            serverAddress: "http://127.0.0.1:9880",
            textLang: "auto",
            refAudioPath: "",
            promptText: "",
            promptLang: "auto"
        )
        self.modelSettings = ModelSettings(modelId: "", language: "auto", autoSplit: "cut0")
        self.chatSettings = ChatSettings(apiURL: "http://localhost:1234", selectedModel: "")
        self.voiceSettings = VoiceSettings(enableStreaming: true)
    }

    // 在 App / ContentView 注入的 SwiftData 上下文
    func attach(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        loadFromStore()
    }

    private func loadFromStore() {
        guard let context else { return }
        let descriptor = FetchDescriptor<AppSettings>(predicate: nil, sortBy: [])
        if let first = try? context.fetch(descriptor).first {
            self.entity = first
        } else {
            let fresh = AppSettings()
            context.insert(fresh)
            self.entity = fresh
            try? context.save()
        }

        guard let e = self.entity else { return }
        self.serverSettings = ServerSettings(
            serverAddress: e.serverAddress,
            textLang: e.textLang,
            refAudioPath: e.refAudioPath,
            promptText: e.promptText,
            promptLang: e.promptLang
        )
        self.modelSettings = ModelSettings(
            modelId: e.modelId, language: e.language, autoSplit: e.autoSplit
        )
        self.chatSettings = ChatSettings(
            apiURL: e.apiURL, selectedModel: e.selectedModel
        )
        self.voiceSettings = VoiceSettings(enableStreaming: e.enableStreaming)
    }

    // MARK: - Update APIs（直接写入 SwiftData）

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

    // MARK: - Persist（SwiftData）

    func saveServerSettings() {
        guard let e = entity, let context else { return }
        e.serverAddress = serverSettings.serverAddress
        e.textLang = serverSettings.textLang
        e.refAudioPath = serverSettings.refAudioPath
        e.promptText = serverSettings.promptText
        e.promptLang = serverSettings.promptLang
        try? context.save()
    }

    func saveModelSettings() {
        guard let e = entity, let context else { return }
        e.modelId = modelSettings.modelId
        e.language = modelSettings.language
        e.autoSplit = modelSettings.autoSplit
        try? context.save()
    }

    func saveChatSettings() {
        guard let e = entity, let context else { return }
        e.apiURL = chatSettings.apiURL
        e.selectedModel = chatSettings.selectedModel
        try? context.save()
    }

    func saveVoiceSettings() {
        guard let e = entity, let context else { return }
        e.enableStreaming = voiceSettings.enableStreaming
        try? context.save()
    }
}
