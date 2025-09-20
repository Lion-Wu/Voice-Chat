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
    // 下面三个已迁移到 VoicePreset，仍保留字段以兼容老库，但不再由业务读取
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
    /// 是否在生成完毕后自动开始朗读
    var autoReadAfterGeneration: Bool
}

// MARK: - 预设实体（SwiftData）

@Model
final class VoicePreset {
    var id: UUID
    var name: String

    // 组内字段（原来散落在 ServerSettings 中的 3 个 + 2 个新权重路径）
    var refAudioPath: String
    var promptText: String
    var promptLang: String
    var gptWeightsPath: String
    var sovitsWeightsPath: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        refAudioPath: String = "",
        promptText: String = "",
        promptLang: String = "auto",
        gptWeightsPath: String = "",
        sovitsWeightsPath: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.refAudioPath = refAudioPath
        self.promptText = promptText
        self.promptLang = promptLang
        self.gptWeightsPath = gptWeightsPath
        self.sovitsWeightsPath = sovitsWeightsPath
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - SwiftData 实体（单行表：保存全局设置）

@Model
final class AppSettings {
    var id: UUID
    var serverAddress: String
    var textLang: String
    // 兼容旧库：以下三个在新版本中改由 VoicePreset 管理
    var refAudioPath: String
    var promptText: String
    var promptLang: String

    var modelId: String
    var language: String
    var autoSplit: String

    var apiURL: String
    var selectedModel: String

    var enableStreaming: Bool
    var autoReadAfterGeneration: Bool?

    // ★ 新增：当前选中的预设 ID
    var selectedPresetID: UUID?

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
        enableStreaming: Bool = true,
        autoReadAfterGeneration: Bool = false,
        selectedPresetID: UUID? = nil
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
        self.autoReadAfterGeneration = autoReadAfterGeneration
        self.selectedPresetID = selectedPresetID
    }
}

// MARK: - Settings Manager（SwiftData 版）

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // 旧结构（仍用于：serverAddress / textLang）
    @Published var serverSettings: ServerSettings
    @Published var modelSettings: ModelSettings
    @Published var chatSettings: ChatSettings
    @Published var voiceSettings: VoiceSettings

    // ★ 预设列表与选择
    @Published private(set) var presets: [VoicePreset] = []
    @Published private(set) var selectedPresetID: UUID?
    var selectedPreset: VoicePreset? { presets.first { $0.id == selectedPresetID } }

    // 应用预设的状态
    @Published private(set) var isApplyingPreset: Bool = false
    @Published private(set) var lastApplyError: String?

    private var context: ModelContext?
    private var entity: AppSettings?

    // 启动只执行一次
    private var didApplyOnLaunch = false

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
        self.voiceSettings = VoiceSettings(enableStreaming: true, autoReadAfterGeneration: false)
    }

    // 在 App / ContentView 注入的 SwiftData 上下文
    func attach(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        loadFromStore()
        loadPresetsFromStore()
        ensureDefaultPresetIfNeeded()
        // 把 entity.selectedPresetID 同步到内存
        self.selectedPresetID = self.entity?.selectedPresetID ?? self.presets.first?.id
    }

    // MARK: - 加载持久化设置

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

        if e.autoReadAfterGeneration == nil {
            e.autoReadAfterGeneration = false
            try? context.save()
        }

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
        self.voiceSettings = VoiceSettings(
            enableStreaming: e.enableStreaming,
            autoReadAfterGeneration: e.autoReadAfterGeneration ?? false
        )
        self.selectedPresetID = e.selectedPresetID
    }

    private func loadPresetsFromStore() {
        guard let context else { return }
        let descriptor = FetchDescriptor<VoicePreset>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let fetched = (try? context.fetch(descriptor)) ?? []
        self.presets = fetched
    }

    private func ensureDefaultPresetIfNeeded() {
        guard let context, let e = entity else { return }
        if presets.isEmpty {
            // 从旧库字段构建一个默认预设
            let def = VoicePreset(
                name: "Default",
                refAudioPath: e.refAudioPath,
                promptText: e.promptText,
                promptLang: e.promptLang,
                gptWeightsPath: "",
                sovitsWeightsPath: ""
            )
            context.insert(def)
            try? context.save()
            self.presets = [def]
            e.selectedPresetID = def.id
            try? context.save()
            self.selectedPresetID = def.id
        } else {
            // 如果还没选中，默认选第一个
            if e.selectedPresetID == nil {
                e.selectedPresetID = presets.first?.id
                try? context.save()
                self.selectedPresetID = e.selectedPresetID
            }
        }
    }

    // MARK: - 更新经典设置（保留）

    func updateServerSettings(serverAddress: String, textLang: String, refAudioPath: String, promptText: String, promptLang: String) {
        // 注意：refAudioPath/promptText/promptLang 已迁移至预设，这里仅维持老库字段，以兼容历史数据
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

    func updateVoiceSettings(enableStreaming: Bool, autoReadAfterGeneration: Bool) {
        voiceSettings.enableStreaming = enableStreaming
        voiceSettings.autoReadAfterGeneration = autoReadAfterGeneration
        saveVoiceSettings()
    }

    // MARK: - 预设 CRUD

    func createPreset(name: String = "New Preset") -> VoicePreset? {
        guard let context else { return nil }
        let p = VoicePreset(
            name: name,
            refAudioPath: "",
            promptText: "",
            promptLang: "auto",
            gptWeightsPath: "",
            sovitsWeightsPath: ""
        )
        context.insert(p)
        try? context.save()
        loadPresetsFromStore()
        return p
    }

    func deletePreset(_ id: UUID) {
        guard let context else { return }
        if let target = presets.first(where: { $0.id == id }) {
            // 若删除的是当前选中，则切到其他
            if selectedPresetID == id {
                let fallback = presets.first(where: { $0.id != id })?.id
                selectedPresetID = fallback
                entity?.selectedPresetID = fallback
            }
            context.delete(target)
            try? context.save()
            loadPresetsFromStore()
        }
    }

    func updatePreset(
        id: UUID,
        name: String? = nil,
        refAudioPath: String? = nil,
        promptText: String? = nil,
        promptLang: String? = nil,
        gptWeightsPath: String? = nil,
        sovitsWeightsPath: String? = nil
    ) {
        guard let context else { return }
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        if let name = name { preset.name = name }
        if let v = refAudioPath { preset.refAudioPath = v }
        if let v = promptText { preset.promptText = v }
        if let v = promptLang { preset.promptLang = v }
        if let v = gptWeightsPath { preset.gptWeightsPath = v }
        if let v = sovitsWeightsPath { preset.sovitsWeightsPath = v }
        preset.updatedAt = Date()
        try? context.save()
        loadPresetsFromStore()
    }

    func selectPreset(_ id: UUID?, apply: Bool = true) {
        guard let context, let e = entity else { return }
        if selectedPresetID == id { return }
        self.selectedPresetID = id
        e.selectedPresetID = id
        try? context.save()
        if apply { Task { await self.applySelectedPreset() } }
    }

    // MARK: - 持久化经典设置

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
        e.autoReadAfterGeneration = voiceSettings.autoReadAfterGeneration
        try? context.save()
    }

    // MARK: - 预设应用（顺序调用两个权重 API）

    func applyPresetOnLaunchIfNeeded() async {
        guard !didApplyOnLaunch else { return }
        didApplyOnLaunch = true
        await applySelectedPreset()
    }

    func applySelectedPreset() async {
        guard let preset = selectedPreset else { return }
        guard !isApplyingPreset else { return }

        isApplyingPreset = true
        lastApplyError = nil
        defer { isApplyingPreset = false }

        // 先更新旧库中三个字段，保证其它地方读取到的兼容值同步（虽然 TTS 已改用 selectedPreset）
        serverSettings.refAudioPath = preset.refAudioPath
        serverSettings.promptText = preset.promptText
        serverSettings.promptLang = preset.promptLang
        saveServerSettings()

        // 构造 URL（兼容 serverAddress 末尾是否有 /）
        func buildURL(_ path: String, weightsPath: String) -> URL? {
            let base = serverSettings.serverAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var comps = URLComponents(string: base + path)
            comps?.queryItems = [URLQueryItem(name: "weights_path", value: weightsPath)]
            return comps?.url
        }

        // 1) set_gpt_weights
        if let url1 = buildURL("/set_gpt_weights", weightsPath: preset.gptWeightsPath) {
            do {
                let (data, resp) = try await URLSession.shared.data(from: url1)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    lastApplyError = "Set GPT weights failed (HTTP \(code))"
                    return
                }
                if let s = String(data: data, encoding: .utf8),
                   s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "success" {
                    // 某些实现只返回空 body，这里不强制失败
                }
            } catch {
                lastApplyError = "Set GPT weights failed: \(error.localizedDescription)"
                return
            }
        } else {
            lastApplyError = "Invalid server address for GPT weights"
            return
        }

        // 2) set_sovits_weights
        if let url2 = buildURL("/set_sovits_weights", weightsPath: preset.sovitsWeightsPath) {
            do {
                let (data, resp) = try await URLSession.shared.data(from: url2)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    lastApplyError = "Set SoVITS weights failed (HTTP \(code))"
                    return
                }
                if let s = String(data: data, encoding: .utf8),
                   s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "success" {
                    // 同上，不强制
                }
            } catch {
                lastApplyError = "Set SoVITS weights failed: \(error.localizedDescription)"
                return
            }
        } else {
            lastApplyError = "Invalid server address for SoVITS weights"
            return
        }
    }
}
