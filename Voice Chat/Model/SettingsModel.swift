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
    // These legacy fields now live on `VoicePreset` but remain for backward compatibility.
    var refAudioPath: String
    var promptText: String
    var promptLang: String
}

struct ModelSettings: Codable, Equatable {
    var modelId: String
    var language: String
    var autoSplit: String
}

struct ChatSettings: Codable, Equatable {
    var apiURL: String
    var selectedModel: String
}

struct VoiceSettings: Codable, Equatable {
    var enableStreaming: Bool
    /// Whether speech playback should start automatically when a response finishes.
    var autoReadAfterGeneration: Bool
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

// MARK: - SwiftData Entity (single-row table storing global settings)

@Model
final class AppSettings {
    var id: UUID
    var serverAddress: String
    var textLang: String
    // Legacy compatibility: these three fields are managed by `VoicePreset` in newer versions.
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
    var developerModeEnabled: Bool?

    // Currently selected preset identifier (optional when nothing is selected).
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
        developerModeEnabled: Bool = false,
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
        self.developerModeEnabled = developerModeEnabled
        self.selectedPresetID = selectedPresetID
    }
}

// MARK: - Settings Manager (SwiftData-backed)

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // Legacy settings still read from the old structure.
    @Published var serverSettings: ServerSettings
    @Published var modelSettings: ModelSettings
    @Published var chatSettings: ChatSettings
    @Published var voiceSettings: VoiceSettings
    @Published var developerModeEnabled: Bool

    // Preset list and selection state.
    @Published private(set) var presets: [VoicePreset] = []
    @Published private(set) var selectedPresetID: UUID?
    var selectedPreset: VoicePreset? { presets.first { $0.id == selectedPresetID } }

    // Tracks whether a preset is being applied and the last error, if any.
    @Published private(set) var isApplyingPreset: Bool = false
    @Published private(set) var lastApplyError: String?

    private var context: ModelContext?
    private var entity: AppSettings?
    private var pendingDeveloperModeEnabled: Bool?

    // Used to gate one-time work performed at launch.
    private var didApplyOnLaunch = false

    private init() {
        // Initialise with defaults until `attach(context:)` loads persisted data.
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
        self.developerModeEnabled = false
    }

    // SwiftData context injected from the app or root view.
    func attach(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        loadFromStore()
        if let pending = pendingDeveloperModeEnabled {
            developerModeEnabled = pending
            entity?.developerModeEnabled = pending
            try? context.save()
            pendingDeveloperModeEnabled = nil
        }
        loadPresetsFromStore()
        ensureDefaultPresetIfNeeded()
        // Keep the in-memory preset selection aligned with persisted data.
        self.selectedPresetID = self.entity?.selectedPresetID ?? self.presets.first?.id
    }

    // MARK: - Load persisted settings

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

        if e.developerModeEnabled == nil {
            e.developerModeEnabled = false
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
        self.developerModeEnabled = e.developerModeEnabled ?? false
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
            // Build a default preset using legacy fields when none exist yet.
            let def = VoicePreset(
                name: String(localized: "Default"),
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
            // Default to the first preset when nothing is selected.
            if e.selectedPresetID == nil {
                e.selectedPresetID = presets.first?.id
                try? context.save()
                self.selectedPresetID = e.selectedPresetID
            }
        }
    }

    // MARK: - Update legacy settings

    func updateServerSettings(serverAddress: String, textLang: String, refAudioPath: String, promptText: String, promptLang: String) {
        // Note: these fields are maintained only for backward compatibility; presets hold the canonical values.
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
        try? context.save()
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

    // MARK: - Persist legacy settings

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

    func saveDeveloperModeEnabled() {
        guard let e = entity, let context else { return }
        e.developerModeEnabled = developerModeEnabled
        try? context.save()
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
        lastApplyError = nil
        defer { isApplyingPreset = false }

        // Update the legacy fields first so other components reading them remain in sync, even though TTS uses `selectedPreset`.
        serverSettings.refAudioPath = preset.refAudioPath
        serverSettings.promptText = preset.promptText
        serverSettings.promptLang = preset.promptLang
        saveServerSettings()

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

        // 1) set_gpt_weights
        if let url1 = buildURL("/set_gpt_weights", weightsPath: preset.gptWeightsPath) {
            do {
                let (data, resp) = try await URLSession.shared.data(from: url1)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    lastApplyError = String(format: NSLocalizedString("Set GPT weights failed (HTTP %d)", comment: "Shown when setting GPT weights fails with an HTTP status."), code)
                    return
                }
                if let s = String(data: data, encoding: .utf8),
                   s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "success" {
                    // Some implementations return an empty body; treat that as success.
                }
            } catch {
                lastApplyError = String(format: NSLocalizedString("Set GPT weights failed: %@", comment: "Shown when setting GPT weights fails with an error."), error.localizedDescription)
                return
            }
        } else {
            lastApplyError = NSLocalizedString("Invalid server address for GPT weights", comment: "Shown when the GPT weights endpoint cannot be constructed")
            return
        }

        // 2) set_sovits_weights
        if let url2 = buildURL("/set_sovits_weights", weightsPath: preset.sovitsWeightsPath) {
            do {
                let (data, resp) = try await URLSession.shared.data(from: url2)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    lastApplyError = String(format: NSLocalizedString("Set SoVITS weights failed (HTTP %d)", comment: "Shown when setting SoVITS weights fails with an HTTP status."), code)
                    return
                }
                if let s = String(data: data, encoding: .utf8),
                   s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "success" {
                    // Same handling as above; empty bodies are considered success.
                }
            } catch {
                lastApplyError = String(format: NSLocalizedString("Set SoVITS weights failed: %@", comment: "Shown when setting SoVITS weights fails with an error."), error.localizedDescription)
                return
            }
        } else {
            lastApplyError = NSLocalizedString("Invalid server address for SoVITS weights", comment: "Shown when the SoVITS weights endpoint cannot be constructed")
            return
        }
    }
}
