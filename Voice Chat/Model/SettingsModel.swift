//
//  SettingsModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation
import SwiftData

// MARK: - Value Types (lightweight structures used by the UI)

struct ServerSettings: Codable, Equatable {
    var serverAddress: String
    var textLang: String
}

struct ModelSettings: Codable, Equatable {
    var modelId: String
    var language: String
    var autoSplit: String
}

struct ChatSettings: Codable, Equatable {
    var apiURL: String
    var selectedModel: String
    var apiKey: String
}

struct VoiceSettings: Codable, Equatable {
    var enableStreaming: Bool
}

// MARK: - Preset Entity (SwiftData)

@Model
final class VoicePreset {
    var id: UUID
    var name: String

    // Consolidated fields originally scattered across `ServerSettings` plus weight paths.
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

// MARK: - Chat Server Preset Entity (SwiftData)

@Model
final class ChatServerPreset {
    var id: UUID
    var name: String

    var apiURL: String
    var selectedModel: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        apiURL: String = "",
        selectedModel: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.apiURL = apiURL
        self.selectedModel = selectedModel
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Voice Server Preset Entity (SwiftData)

@Model
final class VoiceServerPreset {
    var id: UUID
    var name: String

    var serverAddress: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        serverAddress: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.serverAddress = serverAddress
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - System Prompt Preset Entity (SwiftData)

@Model
final class SystemPromptPreset {
    var id: UUID
    var name: String

    /// Which mode this preset belongs to ("normal" / "voice").
    /// Nil means the preset was created before mode separation was introduced.
    var mode: String?

    /// Prompt used for normal (text) chat requests.
    var normalPrompt: String
    /// Prompt used for voice (realtime) chat requests.
    var voicePrompt: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        mode: String? = nil,
        normalPrompt: String = "",
        voicePrompt: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.mode = mode
        self.normalPrompt = normalPrompt
        self.voicePrompt = voicePrompt
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - SwiftData Entity (single-row table storing global settings)

@Model
final class AppSettings {
    var id: UUID
    var serverAddress: String
    var textLang: String

    var modelId: String
    var language: String
    var autoSplit: String

    var apiURL: String
    var selectedModel: String
    var selectedChatServerPresetID: UUID?
    var selectedVoiceServerPresetID: UUID?

    var enableStreaming: Bool
    var developerModeEnabled: Bool?

    // Currently selected preset identifier (optional when nothing is selected).
    var selectedPresetID: UUID?

    // Separate selections for normal/voice chat modes.
    var selectedNormalSystemPromptPresetID: UUID?
    var selectedVoiceSystemPromptPresetID: UUID?

    init(
        serverAddress: String = "http://127.0.0.1:9880",
        textLang: String = "auto",
        modelId: String = "",
        language: String = "auto",
        autoSplit: String = "cut0",
        apiURL: String = "http://localhost:1234",
        selectedModel: String = "",
        selectedChatServerPresetID: UUID? = nil,
        selectedVoiceServerPresetID: UUID? = nil,
        enableStreaming: Bool = true,
        developerModeEnabled: Bool = false,
        selectedPresetID: UUID? = nil,
        selectedNormalSystemPromptPresetID: UUID? = nil,
        selectedVoiceSystemPromptPresetID: UUID? = nil
    ) {
        self.id = UUID()
        self.serverAddress = serverAddress
        self.textLang = textLang
        self.modelId = modelId
        self.language = language
        self.autoSplit = autoSplit
        self.apiURL = apiURL
        self.selectedModel = selectedModel
        self.selectedChatServerPresetID = selectedChatServerPresetID
        self.selectedVoiceServerPresetID = selectedVoiceServerPresetID
        self.enableStreaming = enableStreaming
        self.developerModeEnabled = developerModeEnabled
        self.selectedPresetID = selectedPresetID
        self.selectedNormalSystemPromptPresetID = selectedNormalSystemPromptPresetID
        self.selectedVoiceSystemPromptPresetID = selectedVoiceSystemPromptPresetID
    }
}

// MARK: - Settings Manager (SwiftData-backed)

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private enum SystemPromptPresetMode {
        static let normal = "normal"
        static let voice = "voice"
    }

    // Global settings state.
    @Published var serverSettings: ServerSettings
    @Published var modelSettings: ModelSettings
    @Published var chatSettings: ChatSettings
    @Published var voiceSettings: VoiceSettings
    @Published var developerModeEnabled: Bool

    // Voice server preset list and selection state.
    @Published private(set) var voiceServerPresets: [VoiceServerPreset] = []
    @Published private(set) var selectedVoiceServerPresetID: UUID?
    var selectedVoiceServerPreset: VoiceServerPreset? { voiceServerPresets.first { $0.id == selectedVoiceServerPresetID } }

    // Chat server preset list and selection state.
    @Published private(set) var chatServerPresets: [ChatServerPreset] = []
    @Published private(set) var selectedChatServerPresetID: UUID?
    var selectedChatServerPreset: ChatServerPreset? { chatServerPresets.first { $0.id == selectedChatServerPresetID } }

    // Preset list and selection state.
    @Published private(set) var presets: [VoicePreset] = []
    @Published private(set) var selectedPresetID: UUID?
    var selectedPreset: VoicePreset? { presets.first { $0.id == selectedPresetID } }

    // System prompt preset list and selection state.
    @Published private(set) var systemPromptPresets: [SystemPromptPreset] = []
    @Published private(set) var selectedNormalSystemPromptPresetID: UUID?
    @Published private(set) var selectedVoiceSystemPromptPresetID: UUID?

    var selectedNormalSystemPromptPreset: SystemPromptPreset? {
        systemPromptPresets.first { $0.id == selectedNormalSystemPromptPresetID }
    }

    var selectedVoiceSystemPromptPreset: SystemPromptPreset? {
        systemPromptPresets.first { $0.id == selectedVoiceSystemPromptPresetID }
    }

    var normalSystemPromptPresets: [SystemPromptPreset] {
        systemPromptPresets.filter { $0.mode == SystemPromptPresetMode.normal }
    }

    var voiceSystemPromptPresets: [SystemPromptPreset] {
        systemPromptPresets.filter { $0.mode == SystemPromptPresetMode.voice }
    }

    // Tracks whether a preset is being applied and the last error, if any.
    @Published private(set) var isApplyingPreset: Bool = false
    @Published private(set) var isRetryingPresetApply: Bool = false
    @Published private(set) var presetApplyRetryAttempt: Int = 0
    @Published private(set) var presetApplyRetryLastError: String?
    @Published private(set) var lastApplyError: String?
    @Published private(set) var lastPresetApplyAt: Date?
    @Published private(set) var lastPresetApplySucceeded: Bool = false

    private var context: ModelContext?
    private var entity: AppSettings?
    private var pendingDeveloperModeEnabled: Bool?

    // Used to gate one-time work performed at launch.
    private var didApplyOnLaunch = false

    private enum KeychainKeys {
        static let chatServerPresetAPIKeyPrefix = "chat_server_preset_api_key."
    }

    private enum Defaults {
        static let serverAddress = "http://127.0.0.1:9880"
        static let textLang = "auto"
        static let promptLang = "auto"
        static let modelLanguage = "auto"
        static let autoSplit = "cut0"
        static let apiURL = "http://localhost:1234"
        static let enableStreaming = true
        static let developerModeEnabled = false
    }

    private init() {
        // Initialise with defaults until `attach(context:)` loads persisted data.
        self.serverSettings = ServerSettings(
            serverAddress: Defaults.serverAddress,
            textLang: Defaults.textLang
        )
        self.modelSettings = ModelSettings(modelId: "", language: Defaults.modelLanguage, autoSplit: Defaults.autoSplit)
        self.chatSettings = ChatSettings(apiURL: Defaults.apiURL, selectedModel: "", apiKey: "")
        self.voiceSettings = VoiceSettings(enableStreaming: Defaults.enableStreaming)
        self.developerModeEnabled = Defaults.developerModeEnabled
    }

    // SwiftData context injected from the app or root view.
    func attach(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        loadFromStore()
        if let pending = pendingDeveloperModeEnabled {
            developerModeEnabled = pending
            entity?.developerModeEnabled = pending
            saveContext(label: "apply pending developer mode")
            pendingDeveloperModeEnabled = nil
        }
        loadVoiceServerPresetsFromStore()
        ensureDefaultVoiceServerPresetIfNeeded()
        ensureSelectedVoiceServerPresetIsValid()
        loadChatServerPresetsFromStore()
        ensureDefaultChatServerPresetIfNeeded()
        ensureSelectedChatServerPresetIsValid()
        loadPresetsFromStore()
        ensureDefaultPresetIfNeeded()
        ensureSelectedPresetIsValid()
        loadSystemPromptPresetsFromStore()
        ensureDefaultSystemPromptPresetsForModesIfNeeded()
        // Keep the in-memory preset selection aligned with persisted data.
        self.selectedPresetID = self.entity?.selectedPresetID ?? self.presets.first?.id
        self.selectedChatServerPresetID = self.entity?.selectedChatServerPresetID ?? self.chatServerPresets.first?.id
        self.selectedVoiceServerPresetID = self.entity?.selectedVoiceServerPresetID ?? self.voiceServerPresets.first?.id
        ensureSystemPromptSelectionsAreValid()
        self.selectedNormalSystemPromptPresetID = self.entity?.selectedNormalSystemPromptPresetID ?? self.selectedNormalSystemPromptPresetID
        self.selectedVoiceSystemPromptPresetID = self.entity?.selectedVoiceSystemPromptPresetID ?? self.selectedVoiceSystemPromptPresetID
    }

    // MARK: - Load persisted settings

    private func loadFromStore() {
        guard let context else { return }
        let descriptor = FetchDescriptor<AppSettings>(predicate: nil, sortBy: [])
        do {
            let fetched = try context.fetch(descriptor)
            if fetched.isEmpty {
                let fresh = AppSettings()
                context.insert(fresh)
                self.entity = fresh
                try context.save()
            } else {
                let sorted = fetched.sorted { lhs, rhs in
                    lhs.id.uuidString < rhs.id.uuidString
                }
                self.entity = sorted[0]
                for other in sorted.dropFirst() {
                    context.delete(other)
                }
                if sorted.count > 1 {
                    try context.save()
                }
            }
        } catch {
            print("SwiftData fetch AppSettings failed: \(error)")
            // As a last-resort recovery, create a new row so the app remains usable.
            let fresh = AppSettings()
            context.insert(fresh)
            self.entity = fresh
            do {
                try context.save()
            } catch {
                print("SwiftData save AppSettings failed: \(error)")
            }
        }

        guard let e = self.entity else { return }

        self.serverSettings = ServerSettings(
            serverAddress: e.serverAddress,
            textLang: e.textLang
        )
        self.modelSettings = ModelSettings(
            modelId: e.modelId, language: e.language, autoSplit: e.autoSplit
        )
        self.chatSettings = ChatSettings(
            apiURL: e.apiURL,
            selectedModel: e.selectedModel,
            apiKey: loadChatAPIKey(for: e.selectedChatServerPresetID)
        )
        self.voiceSettings = VoiceSettings(enableStreaming: e.enableStreaming)
        self.developerModeEnabled = e.developerModeEnabled ?? false
        self.selectedVoiceServerPresetID = e.selectedVoiceServerPresetID
        self.selectedChatServerPresetID = e.selectedChatServerPresetID
        self.selectedPresetID = e.selectedPresetID
        self.selectedNormalSystemPromptPresetID = e.selectedNormalSystemPromptPresetID
        self.selectedVoiceSystemPromptPresetID = e.selectedVoiceSystemPromptPresetID
    }

    private func saveContext(label: String) {
        guard let context else { return }
        do {
            try context.save()
        } catch {
            print("SwiftData save failed (\(label)): \(error)")
        }
    }

    private func loadChatServerPresetsFromStore() {
        guard let context else { return }
        let descriptor = FetchDescriptor<ChatServerPreset>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            self.chatServerPresets = try context.fetch(descriptor)
        } catch {
            print("SwiftData fetch ChatServerPreset failed: \(error)")
            self.chatServerPresets = []
        }
    }

    private func loadVoiceServerPresetsFromStore() {
        guard let context else { return }
        let descriptor = FetchDescriptor<VoiceServerPreset>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            self.voiceServerPresets = try context.fetch(descriptor)
        } catch {
            print("SwiftData fetch VoiceServerPreset failed: \(error)")
            self.voiceServerPresets = []
        }
    }

    private func loadPresetsFromStore() {
        guard let context else { return }
        let descriptor = FetchDescriptor<VoicePreset>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            self.presets = try context.fetch(descriptor)
        } catch {
            print("SwiftData fetch VoicePreset failed: \(error)")
            self.presets = []
        }
    }

    private func loadSystemPromptPresetsFromStore() {
        guard let context else { return }
        let descriptor = FetchDescriptor<SystemPromptPreset>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            self.systemPromptPresets = try context.fetch(descriptor)
        } catch {
            print("SwiftData fetch SystemPromptPreset failed: \(error)")
            self.systemPromptPresets = []
        }
    }

    private func ensureDefaultChatServerPresetIfNeeded() {
        guard let context, let e = entity else { return }

        if chatServerPresets.isEmpty {
            let def = ChatServerPreset(
                name: String(localized: "Default"),
                apiURL: e.apiURL,
                selectedModel: e.selectedModel
            )
            context.insert(def)
            saveContext(label: "insert default chat server preset")
            self.chatServerPresets = [def]

            e.selectedChatServerPresetID = def.id
            saveContext(label: "select default chat server preset")
            self.selectedChatServerPresetID = def.id
            applySelectedChatServerPresetToChatSettings()
            return
        }

        if e.selectedChatServerPresetID == nil {
            e.selectedChatServerPresetID = chatServerPresets.first?.id
            saveContext(label: "seed selectedChatServerPresetID")
        }
        self.selectedChatServerPresetID = e.selectedChatServerPresetID
        applySelectedChatServerPresetToChatSettings()
    }

    private func ensureDefaultVoiceServerPresetIfNeeded() {
        guard let context, let e = entity else { return }

        if voiceServerPresets.isEmpty {
            let def = VoiceServerPreset(
                name: String(localized: "Default"),
                serverAddress: e.serverAddress
            )
            context.insert(def)
            saveContext(label: "insert default voice server preset")
            self.voiceServerPresets = [def]

            e.selectedVoiceServerPresetID = def.id
            saveContext(label: "select default voice server preset")
            self.selectedVoiceServerPresetID = def.id
            applySelectedVoiceServerPresetToServerSettings()
            return
        }

        if e.selectedVoiceServerPresetID == nil {
            e.selectedVoiceServerPresetID = voiceServerPresets.first?.id
            saveContext(label: "seed selectedVoiceServerPresetID")
        }
        self.selectedVoiceServerPresetID = e.selectedVoiceServerPresetID
        applySelectedVoiceServerPresetToServerSettings()
    }

    private func ensureSelectedChatServerPresetIsValid() {
        guard context != nil, let e = entity else { return }
        guard !chatServerPresets.isEmpty else { return }

        if let selected = e.selectedChatServerPresetID,
           chatServerPresets.contains(where: { $0.id == selected }) {
            self.selectedChatServerPresetID = selected
            applySelectedChatServerPresetToChatSettings()
            return
        }

        let fallback = chatServerPresets.first?.id
        e.selectedChatServerPresetID = fallback
        self.selectedChatServerPresetID = fallback
        saveContext(label: "repair selectedChatServerPresetID")
        applySelectedChatServerPresetToChatSettings()
    }

    private func ensureSelectedVoiceServerPresetIsValid() {
        guard context != nil, let e = entity else { return }
        guard !voiceServerPresets.isEmpty else { return }

        if let selected = e.selectedVoiceServerPresetID,
           voiceServerPresets.contains(where: { $0.id == selected }) {
            self.selectedVoiceServerPresetID = selected
            applySelectedVoiceServerPresetToServerSettings()
            return
        }

        let fallback = voiceServerPresets.first?.id
        e.selectedVoiceServerPresetID = fallback
        self.selectedVoiceServerPresetID = fallback
        saveContext(label: "repair selectedVoiceServerPresetID")
        applySelectedVoiceServerPresetToServerSettings()
    }

    private func ensureDefaultPresetIfNeeded() {
        guard let context, let e = entity else { return }
        if presets.isEmpty {
            let def = VoicePreset(
                name: String(localized: "Default"),
                refAudioPath: "",
                promptText: "",
                promptLang: Defaults.promptLang,
                gptWeightsPath: "",
                sovitsWeightsPath: ""
            )
            context.insert(def)
            saveContext(label: "insert default voice preset")
            self.presets = [def]
            e.selectedPresetID = def.id
            saveContext(label: "select default voice preset")
            self.selectedPresetID = def.id
        } else {
            // Default to the first preset when nothing is selected.
            if e.selectedPresetID == nil {
                e.selectedPresetID = presets.first?.id
                saveContext(label: "seed selectedPresetID")
                self.selectedPresetID = e.selectedPresetID
            }
        }
    }

    private func ensureSelectedPresetIsValid() {
        guard context != nil, let e = entity else { return }
        guard !presets.isEmpty else { return }

        if let selected = e.selectedPresetID, presets.contains(where: { $0.id == selected }) {
            self.selectedPresetID = selected
            return
        }

        let fallback = presets.first?.id
        e.selectedPresetID = fallback
        self.selectedPresetID = fallback
        saveContext(label: "repair selectedPresetID")
    }

    private func ensureDefaultSystemPromptPresetsForModesIfNeeded() {
        guard let context else { return }
        var didChange = false

        if normalSystemPromptPresets.isEmpty {
            let def = SystemPromptPreset(
                name: String(localized: "Default"),
                mode: SystemPromptPresetMode.normal
            )
            context.insert(def)
            didChange = true
        }

        if voiceSystemPromptPresets.isEmpty {
            let def = SystemPromptPreset(
                name: String(localized: "Default"),
                mode: SystemPromptPresetMode.voice
            )
            context.insert(def)
            didChange = true
        }

        if didChange {
            saveContext(label: "ensure default system prompt presets")
            loadSystemPromptPresetsFromStore()
        }
    }

    private func ensureSystemPromptSelectionsAreValid() {
        guard context != nil, let e = entity else { return }
        guard let normalFallback = normalSystemPromptPresets.first?.id else { return }
        guard let voiceFallback = voiceSystemPromptPresets.first?.id else { return }

        let byID: [UUID: SystemPromptPreset] = Dictionary(uniqueKeysWithValues: systemPromptPresets.map { ($0.id, $0) })
        var didChange = false

        let desiredNormal = selectedNormalSystemPromptPresetID
            ?? e.selectedNormalSystemPromptPresetID
        if let desiredNormal,
           let preset = byID[desiredNormal],
           preset.mode == SystemPromptPresetMode.normal {
            selectedNormalSystemPromptPresetID = desiredNormal
            e.selectedNormalSystemPromptPresetID = desiredNormal
        } else {
            selectedNormalSystemPromptPresetID = normalFallback
            e.selectedNormalSystemPromptPresetID = normalFallback
            didChange = true
        }

        let desiredVoice = selectedVoiceSystemPromptPresetID
            ?? e.selectedVoiceSystemPromptPresetID
        if let desiredVoice,
           let preset = byID[desiredVoice],
           preset.mode == SystemPromptPresetMode.voice {
            selectedVoiceSystemPromptPresetID = desiredVoice
            e.selectedVoiceSystemPromptPresetID = desiredVoice
        } else {
            selectedVoiceSystemPromptPresetID = voiceFallback
            e.selectedVoiceSystemPromptPresetID = voiceFallback
            didChange = true
        }

        if didChange {
            saveContext(label: "repair system prompt selections")
        }
    }

    // MARK: - Update settings

    func updateServerSettings(serverAddress: String, textLang: String) {
        serverSettings.serverAddress = serverAddress
        serverSettings.textLang = textLang
        saveServerSettings()

        guard context != nil else { return }
        guard let presetID = selectedVoiceServerPresetID,
              let preset = voiceServerPresets.first(where: { $0.id == presetID }) else { return }

        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let presetTrimmed = preset.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != presetTrimmed else { return }

        preset.serverAddress = serverAddress
        preset.updatedAt = Date()
        saveContext(label: "update voice server preset")
        loadVoiceServerPresetsFromStore()
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

        guard context != nil else { return }
        guard let presetID = selectedChatServerPresetID,
              let preset = chatServerPresets.first(where: { $0.id == presetID }) else { return }
        preset.apiURL = apiURL
        preset.selectedModel = selectedModel
        preset.updatedAt = Date()
        saveContext(label: "update chat server preset")
        loadChatServerPresetsFromStore()
    }

    func updateChatAPIKey(_ apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        chatSettings.apiKey = trimmed
        saveChatAPIKey(trimmed, for: selectedChatServerPresetID)

        guard context != nil else { return }
        guard let presetID = selectedChatServerPresetID,
              let preset = chatServerPresets.first(where: { $0.id == presetID }) else { return }
        preset.updatedAt = Date()
        saveContext(label: "touch chat server preset api key")
        loadChatServerPresetsFromStore()
    }

    func updateVoiceSettings(enableStreaming: Bool) {
        voiceSettings.enableStreaming = enableStreaming
        saveVoiceSettings()
    }

    // MARK: - Voice server preset CRUD

    func createVoiceServerPreset(name: String = String(localized: "New Preset")) -> VoiceServerPreset? {
        guard let context else { return nil }
        let p = VoiceServerPreset(
            name: name,
            serverAddress: serverSettings.serverAddress
        )
        context.insert(p)
        saveContext(label: "create voice server preset")
        loadVoiceServerPresetsFromStore()
        return p
    }

    func deleteVoiceServerPreset(_ id: UUID) {
        guard let context else { return }
        if let target = voiceServerPresets.first(where: { $0.id == id }) {
            if selectedVoiceServerPresetID == id {
                let fallback = voiceServerPresets.first(where: { $0.id != id })?.id
                selectedVoiceServerPresetID = fallback
                entity?.selectedVoiceServerPresetID = fallback
            }
            context.delete(target)
            saveContext(label: "delete voice server preset")
            loadVoiceServerPresetsFromStore()
            ensureSelectedVoiceServerPresetIsValid()
        }
    }

    func updateVoiceServerPreset(
        id: UUID,
        name: String? = nil
    ) {
        guard context != nil else { return }
        guard let preset = voiceServerPresets.first(where: { $0.id == id }) else { return }
        if let name { preset.name = name }
        preset.updatedAt = Date()
        saveContext(label: "update voice server preset meta")
        loadVoiceServerPresetsFromStore()
    }

    func selectVoiceServerPreset(_ id: UUID?) {
        guard context != nil, let e = entity else { return }
        if selectedVoiceServerPresetID == id { return }
        selectedVoiceServerPresetID = id
        e.selectedVoiceServerPresetID = id
        saveContext(label: "select voice server preset")
        applySelectedVoiceServerPresetToServerSettings()
    }

    // MARK: - Chat server preset CRUD

    func createChatServerPreset(name: String = String(localized: "New Preset")) -> ChatServerPreset? {
        guard let context else { return nil }
        let p = ChatServerPreset(
            name: name,
            apiURL: chatSettings.apiURL,
            selectedModel: chatSettings.selectedModel
        )
        context.insert(p)
        saveContext(label: "create chat server preset")
        saveChatAPIKey(chatSettings.apiKey, for: p.id)
        loadChatServerPresetsFromStore()
        return p
    }

    func deleteChatServerPreset(_ id: UUID) {
        guard let context else { return }
        if let target = chatServerPresets.first(where: { $0.id == id }) {
            if selectedChatServerPresetID == id {
                let fallback = chatServerPresets.first(where: { $0.id != id })?.id
                selectedChatServerPresetID = fallback
                entity?.selectedChatServerPresetID = fallback
            }
            context.delete(target)
            saveContext(label: "delete chat server preset")
            deleteChatAPIKey(for: id)
            loadChatServerPresetsFromStore()
            ensureSelectedChatServerPresetIsValid()
        }
    }

    func updateChatServerPreset(
        id: UUID,
        name: String? = nil
    ) {
        guard context != nil else { return }
        guard let preset = chatServerPresets.first(where: { $0.id == id }) else { return }
        if let name { preset.name = name }
        preset.updatedAt = Date()
        saveContext(label: "update chat server preset meta")
        loadChatServerPresetsFromStore()
    }

    func selectChatServerPreset(_ id: UUID?) {
        guard context != nil, let e = entity else { return }
        if selectedChatServerPresetID == id { return }
        selectedChatServerPresetID = id
        e.selectedChatServerPresetID = id
        saveContext(label: "select chat server preset")
        applySelectedChatServerPresetToChatSettings()
    }

    func updateDeveloperModeEnabled(_ enabled: Bool) {
        developerModeEnabled = enabled
        guard entity != nil, context != nil else {
            pendingDeveloperModeEnabled = enabled
            return
        }
        saveDeveloperModeEnabled()
    }

    // MARK: - Preset CRUD

    func createPreset(name: String = String(localized: "New Preset")) -> VoicePreset? {
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
        saveContext(label: "create preset")
        loadPresetsFromStore()
        return p
    }

    func deletePreset(_ id: UUID) {
        guard let context else { return }
        if let target = presets.first(where: { $0.id == id }) {
            // If the active preset is removed, switch to another one.
            if selectedPresetID == id {
                let fallback = presets.first(where: { $0.id != id })?.id
                selectedPresetID = fallback
                entity?.selectedPresetID = fallback
            }
            context.delete(target)
            saveContext(label: "delete preset")
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
        guard context != nil else { return }
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        if let name = name { preset.name = name }
        if let v = refAudioPath { preset.refAudioPath = v }
        if let v = promptText { preset.promptText = v }
        if let v = promptLang { preset.promptLang = v }
        if let v = gptWeightsPath { preset.gptWeightsPath = v }
        if let v = sovitsWeightsPath { preset.sovitsWeightsPath = v }
        preset.updatedAt = Date()
        saveContext(label: "update preset")
        loadPresetsFromStore()
    }

    func selectPreset(_ id: UUID?, apply: Bool = true) {
        guard context != nil, let e = entity else { return }
        if selectedPresetID == id { return }
        self.selectedPresetID = id
        e.selectedPresetID = id
        saveContext(label: "select preset")
        if apply { Task { await self.applySelectedPreset() } }
    }

    // MARK: - System prompt preset CRUD

    func createNormalSystemPromptPreset(name: String = String(localized: "New Prompt Preset")) -> SystemPromptPreset? {
        createSystemPromptPreset(mode: SystemPromptPresetMode.normal, name: name)
    }

    func createVoiceSystemPromptPreset(name: String = String(localized: "New Prompt Preset")) -> SystemPromptPreset? {
        createSystemPromptPreset(mode: SystemPromptPresetMode.voice, name: name)
    }

    private func createSystemPromptPreset(mode: String, name: String) -> SystemPromptPreset? {
        guard let context else { return nil }
        let preset = SystemPromptPreset(name: name, mode: mode, normalPrompt: "", voicePrompt: "")
        context.insert(preset)
        saveContext(label: "create system prompt preset")
        loadSystemPromptPresetsFromStore()
        return preset
    }

    func deleteSystemPromptPreset(_ id: UUID) {
        guard let context else { return }
        if let target = systemPromptPresets.first(where: { $0.id == id }) {
            context.delete(target)
            saveContext(label: "delete system prompt preset")
            loadSystemPromptPresetsFromStore()
            ensureDefaultSystemPromptPresetsForModesIfNeeded()
            ensureSystemPromptSelectionsAreValid()
        }
    }

    func updateNormalSystemPromptPreset(
        id: UUID,
        name: String? = nil,
        prompt: String? = nil
    ) {
        guard context != nil else { return }
        guard let preset = systemPromptPresets.first(where: { $0.id == id }) else { return }
        preset.mode = SystemPromptPresetMode.normal
        if let name { preset.name = name }
        if let prompt { preset.normalPrompt = prompt }
        preset.voicePrompt = ""
        preset.updatedAt = Date()
        saveContext(label: "update normal system prompt preset")
        loadSystemPromptPresetsFromStore()
    }

    func updateVoiceSystemPromptPreset(
        id: UUID,
        name: String? = nil,
        prompt: String? = nil
    ) {
        guard context != nil else { return }
        guard let preset = systemPromptPresets.first(where: { $0.id == id }) else { return }
        preset.mode = SystemPromptPresetMode.voice
        if let name { preset.name = name }
        if let prompt { preset.voicePrompt = prompt }
        preset.normalPrompt = ""
        preset.updatedAt = Date()
        saveContext(label: "update voice system prompt preset")
        loadSystemPromptPresetsFromStore()
    }

    func updateSystemPromptPreset(
        id: UUID,
        name: String? = nil,
        normalPrompt: String? = nil,
        voicePrompt: String? = nil
    ) {
        guard context != nil else { return }
        guard let preset = systemPromptPresets.first(where: { $0.id == id }) else { return }
        if let name { preset.name = name }
        if let normalPrompt { preset.normalPrompt = normalPrompt }
        if let voicePrompt { preset.voicePrompt = voicePrompt }
        preset.updatedAt = Date()
        saveContext(label: "update system prompt preset")
        loadSystemPromptPresetsFromStore()
    }

    func selectNormalSystemPromptPreset(_ id: UUID?) {
        guard context != nil, let e = entity else { return }
        if selectedNormalSystemPromptPresetID == id { return }
        selectedNormalSystemPromptPresetID = id
        e.selectedNormalSystemPromptPresetID = id
        saveContext(label: "select normal system prompt preset")
    }

    func selectVoiceSystemPromptPreset(_ id: UUID?) {
        guard context != nil, let e = entity else { return }
        if selectedVoiceSystemPromptPresetID == id { return }
        selectedVoiceSystemPromptPresetID = id
        e.selectedVoiceSystemPromptPresetID = id
        saveContext(label: "select voice system prompt preset")
    }

    // MARK: - Persist settings

    func saveServerSettings() {
        guard let e = entity, context != nil else { return }
        e.serverAddress = serverSettings.serverAddress
        e.textLang = serverSettings.textLang
        saveContext(label: "save server settings")
    }

    func saveModelSettings() {
        guard let e = entity, context != nil else { return }
        e.modelId = modelSettings.modelId
        e.language = modelSettings.language
        e.autoSplit = modelSettings.autoSplit
        saveContext(label: "save model settings")
    }

    func saveChatSettings() {
        guard let e = entity, context != nil else { return }
        e.apiURL = chatSettings.apiURL
        e.selectedModel = chatSettings.selectedModel
        saveContext(label: "save chat settings")
    }

    private func keychainAccount(forChatServerPresetID id: UUID) -> String {
        "\(KeychainKeys.chatServerPresetAPIKeyPrefix)\(id.uuidString)"
    }

    private func loadChatAPIKey(for presetID: UUID?) -> String {
        let service = Bundle.main.bundleIdentifier ?? "VoiceChat"
        guard let presetID else { return "" }
        let account = keychainAccount(forChatServerPresetID: presetID)
        return (KeychainStore.loadString(service: service, account: account) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveChatAPIKey(_ apiKey: String, for presetID: UUID?) {
        guard let presetID else { return }
        let service = Bundle.main.bundleIdentifier ?? "VoiceChat"
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = keychainAccount(forChatServerPresetID: presetID)

        if trimmed.isEmpty {
            KeychainStore.delete(service: service, account: account)
        } else {
            KeychainStore.saveString(trimmed, service: service, account: account)
        }
    }

    private func deleteChatAPIKey(for presetID: UUID) {
        let service = Bundle.main.bundleIdentifier ?? "VoiceChat"
        let account = keychainAccount(forChatServerPresetID: presetID)
        KeychainStore.delete(service: service, account: account)
    }

    private func applySelectedChatServerPresetToChatSettings() {
        guard let preset = selectedChatServerPreset else { return }
        chatSettings.apiURL = preset.apiURL
        chatSettings.selectedModel = preset.selectedModel
        chatSettings.apiKey = loadChatAPIKey(for: preset.id)
        saveChatSettings()
    }

    private func applySelectedVoiceServerPresetToServerSettings() {
        guard let preset = selectedVoiceServerPreset else { return }
        serverSettings.serverAddress = preset.serverAddress
        saveServerSettings()
    }

    func saveVoiceSettings() {
        guard let e = entity, context != nil else { return }
        e.enableStreaming = voiceSettings.enableStreaming
        saveContext(label: "save voice settings")
    }

    func saveDeveloperModeEnabled() {
        guard let e = entity, context != nil else { return }
        e.developerModeEnabled = developerModeEnabled
        saveContext(label: "save developer mode")
    }

    // MARK: - Apply presets (invokes the weight APIs sequentially)

    func applyPresetOnLaunchIfNeeded() async {
        guard !didApplyOnLaunch else { return }
        didApplyOnLaunch = true
        await applySelectedPreset()
    }

    func applySelectedPreset() async {
        guard let preset = selectedPreset else { return }
        guard !isApplyingPreset else { return }

        isApplyingPreset = true
        isRetryingPresetApply = false
        presetApplyRetryAttempt = 0
        presetApplyRetryLastError = nil
        lastApplyError = nil
        lastPresetApplyAt = nil
        lastPresetApplySucceeded = false
        defer {
            isApplyingPreset = false
            isRetryingPresetApply = false
            presetApplyRetryAttempt = 0
            presetApplyRetryLastError = nil
        }

        // Build URLs while being tolerant of trailing slashes in `serverAddress`.
        func buildURL(_ path: String, weightsPath: String) -> URL? {
            let raw = serverSettings.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            let normalized = raw.contains("://") ? raw : "http://\(raw)"
            let base = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var comps = URLComponents(string: base + path)
            comps?.queryItems = [URLQueryItem(name: "weights_path", value: weightsPath)]
            return comps?.url
        }

        func recordFailure(_ message: String) {
            lastApplyError = message
            lastPresetApplyAt = Date()
            lastPresetApplySucceeded = false
            isRetryingPresetApply = false
            presetApplyRetryAttempt = 0
            presetApplyRetryLastError = nil
        }

        func recordSuccess() {
            lastApplyError = nil
            lastPresetApplyAt = Date()
            lastPresetApplySucceeded = true
            isRetryingPresetApply = false
            presetApplyRetryAttempt = 0
            presetApplyRetryLastError = nil
        }

        let retryPolicy = NetworkRetryPolicy(
            maxAttempts: 4,
            baseDelay: 0.5,
            maxDelay: 4.0,
            backoffFactor: 1.6,
            jitterRatio: 0.2
        )

        func fetchWithRetry(_ url: URL) async throws -> Data {
            let (data, _) = try await NetworkRetry.run(
                policy: retryPolicy,
                onRetry: { nextAttempt, _, error in
                    await MainActor.run {
                        self.isRetryingPresetApply = true
                        self.presetApplyRetryAttempt = max(1, nextAttempt - 1)
                        self.presetApplyRetryLastError = error.localizedDescription
                    }
                },
                operation: {
                    let (data, resp) = try await URLSession.shared.data(from: url)
                    if let http = resp as? HTTPURLResponse,
                       !(200...299).contains(http.statusCode) {
                        let preview = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let snippet = preview.isEmpty ? nil : String(preview.prefix(180))
                        throw HTTPStatusError(statusCode: http.statusCode, bodyPreview: snippet)
                    }
                    return (data, resp)
                }
            )
            await MainActor.run {
                self.isRetryingPresetApply = false
                self.presetApplyRetryAttempt = 0
                self.presetApplyRetryLastError = nil
            }
            return data
        }

        // 1) set_gpt_weights
        if let url1 = buildURL("/set_gpt_weights", weightsPath: preset.gptWeightsPath) {
            do {
                let data = try await fetchWithRetry(url1)
                if let s = String(data: data, encoding: .utf8),
                   s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "success" {
                    // Some implementations return an empty body; treat that as success.
                }
            } catch {
                if let statusError = error as? HTTPStatusError {
                    recordFailure(String(format: NSLocalizedString("Set GPT weights failed (HTTP %d)", comment: "Shown when setting GPT weights fails with an HTTP status."), statusError.statusCode))
                } else {
                    recordFailure(String(format: NSLocalizedString("Set GPT weights failed: %@", comment: "Shown when setting GPT weights fails with an error."), error.localizedDescription))
                }
                return
            }
        } else {
            recordFailure(NSLocalizedString("Invalid server address for GPT weights", comment: "Shown when the GPT weights endpoint cannot be constructed"))
            return
        }

        // 2) set_sovits_weights
        if let url2 = buildURL("/set_sovits_weights", weightsPath: preset.sovitsWeightsPath) {
            do {
                let data = try await fetchWithRetry(url2)
                if let s = String(data: data, encoding: .utf8),
                   s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "success" {
                    // Same handling as above; empty bodies are considered success.
                }
            } catch {
                if let statusError = error as? HTTPStatusError {
                    recordFailure(String(format: NSLocalizedString("Set SoVITS weights failed (HTTP %d)", comment: "Shown when setting SoVITS weights fails with an HTTP status."), statusError.statusCode))
                } else {
                    recordFailure(String(format: NSLocalizedString("Set SoVITS weights failed: %@", comment: "Shown when setting SoVITS weights fails with an error."), error.localizedDescription))
                }
                return
            }
        } else {
            recordFailure(NSLocalizedString("Invalid server address for SoVITS weights", comment: "Shown when the SoVITS weights endpoint cannot be constructed"))
            return
        }

        recordSuccess()
    }
}
