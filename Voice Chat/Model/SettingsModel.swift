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
    var developerModeEnabled: Bool?

    // Currently selected preset identifier (optional when nothing is selected).
    var selectedPresetID: UUID?

    // Legacy (v1): single selected system prompt preset identifier.
    var selectedSystemPromptPresetID: UUID?

    // v2: separate selections for normal/voice chat modes.
    var selectedNormalSystemPromptPresetID: UUID?
    var selectedVoiceSystemPromptPresetID: UUID?

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
        developerModeEnabled: Bool = false,
        selectedPresetID: UUID? = nil,
        selectedSystemPromptPresetID: UUID? = nil,
        selectedNormalSystemPromptPresetID: UUID? = nil,
        selectedVoiceSystemPromptPresetID: UUID? = nil
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
        self.developerModeEnabled = developerModeEnabled
        self.selectedPresetID = selectedPresetID
        self.selectedSystemPromptPresetID = selectedSystemPromptPresetID
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
    @Published private(set) var lastApplyError: String?

    private var context: ModelContext?
    private var entity: AppSettings?
    private var pendingDeveloperModeEnabled: Bool?

    // Used to gate one-time work performed at launch.
    private var didApplyOnLaunch = false

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
            textLang: Defaults.textLang,
            refAudioPath: "",
            promptText: "",
            promptLang: Defaults.promptLang
        )
        self.modelSettings = ModelSettings(modelId: "", language: Defaults.modelLanguage, autoSplit: Defaults.autoSplit)
        self.chatSettings = ChatSettings(apiURL: Defaults.apiURL, selectedModel: "")
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
        loadPresetsFromStore()
        ensureDefaultPresetIfNeeded()
        ensureSelectedPresetIsValid()
        loadSystemPromptPresetsFromStore()
        migrateLegacySystemPromptPresetsIfNeeded()
        ensureDefaultSystemPromptPresetsForModesIfNeeded()
        // Keep the in-memory preset selection aligned with persisted data.
        self.selectedPresetID = self.entity?.selectedPresetID ?? self.presets.first?.id
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
            } else if fetched.count == 1 {
                self.entity = fetched[0]
            } else {
                // If multiple rows exist (e.g. from earlier versions or intermittent fetch/save failures),
                // pick a deterministic "best" row and remove the rest to avoid random blank settings at launch.
                let best = pickBestAppSettings(from: fetched)
                mergeAppSettings(into: best, from: fetched)
                self.entity = best
                for other in fetched where other !== best {
                    context.delete(other)
                }
                try context.save()
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

        if e.developerModeEnabled == nil {
            e.developerModeEnabled = Defaults.developerModeEnabled
            saveContext(label: "seed developerModeEnabled")
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
        self.voiceSettings = VoiceSettings(enableStreaming: e.enableStreaming)
        self.developerModeEnabled = e.developerModeEnabled ?? false
        self.selectedPresetID = e.selectedPresetID
        self.selectedNormalSystemPromptPresetID = e.selectedNormalSystemPromptPresetID
        self.selectedVoiceSystemPromptPresetID = e.selectedVoiceSystemPromptPresetID
    }

    private func pickBestAppSettings(from candidates: [AppSettings]) -> AppSettings {
        func normalized(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func isNonEmpty(_ value: String) -> Bool {
            !normalized(value).isEmpty
        }

        func isNonEmptyAndNotDefault(_ value: String, defaultValue: String) -> Bool {
            let trimmed = normalized(value)
            return !trimmed.isEmpty && trimmed != defaultValue
        }

        func score(_ e: AppSettings) -> Int {
            var total = 0
            func add(_ condition: Bool, weight: Int = 1) {
                if condition { total += weight }
            }

            // Empty strings are treated as invalid and should never outscore valid defaults.
            add(isNonEmpty(e.serverAddress), weight: 2)
            add(isNonEmptyAndNotDefault(e.serverAddress, defaultValue: Defaults.serverAddress))

            add(isNonEmpty(e.textLang))
            add(isNonEmptyAndNotDefault(e.textLang, defaultValue: Defaults.textLang))

            add(!normalized(e.refAudioPath).isEmpty, weight: 2)
            add(!normalized(e.promptText).isEmpty)
            add(isNonEmpty(e.promptLang))
            add(isNonEmptyAndNotDefault(e.promptLang, defaultValue: Defaults.promptLang))

            add(!normalized(e.modelId).isEmpty)
            add(isNonEmpty(e.language))
            add(isNonEmptyAndNotDefault(e.language, defaultValue: Defaults.modelLanguage))
            add(isNonEmpty(e.autoSplit))
            add(isNonEmptyAndNotDefault(e.autoSplit, defaultValue: Defaults.autoSplit))

            add(isNonEmpty(e.apiURL), weight: 2)
            add(isNonEmptyAndNotDefault(e.apiURL, defaultValue: Defaults.apiURL))
            add(!normalized(e.selectedModel).isEmpty, weight: 2)

            add(e.enableStreaming != Defaults.enableStreaming)
            add((e.developerModeEnabled ?? Defaults.developerModeEnabled) != Defaults.developerModeEnabled)

            add(e.selectedPresetID != nil, weight: 2)
            add(e.selectedNormalSystemPromptPresetID != nil, weight: 2)
            add(e.selectedVoiceSystemPromptPresetID != nil, weight: 2)
            add(e.selectedSystemPromptPresetID != nil)
            return total
        }

        let sorted = candidates.sorted { lhs, rhs in
            let lScore = score(lhs)
            let rScore = score(rhs)
            if lScore != rScore {
                return lScore > rScore
            }
            // Stable tie-breaker across launches.
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return sorted[0]
    }

    /// Best-effort merge: only fills in values that are still at defaults on the chosen row.
    private func mergeAppSettings(into best: AppSettings, from candidates: [AppSettings]) {
        func normalized(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func adoptString(_ keyPath: ReferenceWritableKeyPath<AppSettings, String>, defaultValue: String, from other: AppSettings) {
            let current = normalized(best[keyPath: keyPath])
            let candidate = normalized(other[keyPath: keyPath])
            // Never adopt empty strings.
            guard !candidate.isEmpty else { return }

            // If the chosen row has an empty string (invalid), always adopt a non-empty value,
            // even if it equals the default.
            if current.isEmpty {
                best[keyPath: keyPath] = other[keyPath: keyPath]
                return
            }

            // Otherwise, only replace defaults with non-default values.
            guard current == defaultValue else { return }
            guard candidate != defaultValue else { return }
            best[keyPath: keyPath] = other[keyPath: keyPath]
        }

        func adoptOptionalID(_ keyPath: ReferenceWritableKeyPath<AppSettings, UUID?>, from other: AppSettings) {
            guard best[keyPath: keyPath] == nil else { return }
            guard let value = other[keyPath: keyPath] else { return }
            best[keyPath: keyPath] = value
        }

        func adoptBool(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>, defaultValue: Bool, from other: AppSettings) {
            guard best[keyPath: keyPath] == defaultValue else { return }
            let candidate = other[keyPath: keyPath]
            guard candidate != defaultValue else { return }
            best[keyPath: keyPath] = candidate
        }

        for other in candidates where other !== best {
            adoptString(\.serverAddress, defaultValue: Defaults.serverAddress, from: other)
            adoptString(\.textLang, defaultValue: Defaults.textLang, from: other)
            adoptString(\.refAudioPath, defaultValue: "", from: other)
            adoptString(\.promptText, defaultValue: "", from: other)
            adoptString(\.promptLang, defaultValue: Defaults.promptLang, from: other)

            adoptString(\.modelId, defaultValue: "", from: other)
            adoptString(\.language, defaultValue: Defaults.modelLanguage, from: other)
            adoptString(\.autoSplit, defaultValue: Defaults.autoSplit, from: other)

            adoptString(\.apiURL, defaultValue: Defaults.apiURL, from: other)
            adoptString(\.selectedModel, defaultValue: "", from: other)

            adoptBool(\.enableStreaming, defaultValue: Defaults.enableStreaming, from: other)
            if best.developerModeEnabled == nil {
                best.developerModeEnabled = other.developerModeEnabled
            }

            adoptOptionalID(\.selectedPresetID, from: other)
            adoptOptionalID(\.selectedSystemPromptPresetID, from: other)
            adoptOptionalID(\.selectedNormalSystemPromptPresetID, from: other)
            adoptOptionalID(\.selectedVoiceSystemPromptPresetID, from: other)
        }
    }

    private func saveContext(label: String) {
        guard let context else { return }
        do {
            try context.save()
        } catch {
            print("SwiftData save failed (\(label)): \(error)")
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

    private func migrateLegacySystemPromptPresetsIfNeeded() {
        guard let context, let e = entity else { return }
        guard !systemPromptPresets.isEmpty else { return }

        func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var didChange = false
        var voiceCloneByOriginalID: [UUID: UUID] = [:]

        for preset in systemPromptPresets {
            let mode = trimmed(preset.mode ?? "")
            let normal = trimmed(preset.normalPrompt)
            let voice = trimmed(preset.voicePrompt)

            if mode == SystemPromptPresetMode.normal {
                if !voice.isEmpty {
                    preset.voicePrompt = ""
                    didChange = true
                }
                continue
            }

            if mode == SystemPromptPresetMode.voice {
                if !normal.isEmpty {
                    preset.normalPrompt = ""
                    didChange = true
                }
                continue
            }

            // Legacy preset (no/unknown mode): split or classify.
            if !normal.isEmpty && !voice.isEmpty {
                let voiceClone = SystemPromptPreset(
                    name: preset.name,
                    mode: SystemPromptPresetMode.voice,
                    normalPrompt: "",
                    voicePrompt: voice
                )
                voiceClone.createdAt = preset.createdAt
                voiceClone.updatedAt = preset.updatedAt
                context.insert(voiceClone)
                voiceCloneByOriginalID[preset.id] = voiceClone.id

                preset.mode = SystemPromptPresetMode.normal
                preset.normalPrompt = normal
                preset.voicePrompt = ""
                didChange = true
                continue
            }

            if !voice.isEmpty {
                preset.mode = SystemPromptPresetMode.voice
                preset.normalPrompt = ""
                preset.voicePrompt = voice
                didChange = true
                continue
            }

            // Default to normal for empty/normal-only presets.
            preset.mode = SystemPromptPresetMode.normal
            preset.normalPrompt = normal
            preset.voicePrompt = ""
            didChange = true
        }

        // Migration: if only the legacy selection exists, populate both new selections.
        if e.selectedNormalSystemPromptPresetID == nil,
           e.selectedVoiceSystemPromptPresetID == nil,
           let legacy = e.selectedSystemPromptPresetID {
            e.selectedNormalSystemPromptPresetID = legacy
            e.selectedVoiceSystemPromptPresetID = legacy
            didChange = true
        }

        // If the voice selection pointed at an old combined preset that was split, map it to the voice clone.
        if let voiceSelection = e.selectedVoiceSystemPromptPresetID,
           let mapped = voiceCloneByOriginalID[voiceSelection] {
            e.selectedVoiceSystemPromptPresetID = mapped
            didChange = true
        }

        if didChange {
            saveContext(label: "migrate system prompt presets")
            loadSystemPromptPresetsFromStore()
        }
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

        let legacySelection = e.selectedSystemPromptPresetID

        let desiredNormal = selectedNormalSystemPromptPresetID
            ?? e.selectedNormalSystemPromptPresetID
            ?? legacySelection
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
            ?? legacySelection
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

        if e.selectedSystemPromptPresetID == nil {
            e.selectedSystemPromptPresetID = selectedNormalSystemPromptPresetID
            didChange = true
        }

        if didChange {
            saveContext(label: "repair system prompt selections")
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

    func updateVoiceSettings(enableStreaming: Bool) {
        voiceSettings.enableStreaming = enableStreaming
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

    // MARK: - Persist legacy settings

    func saveServerSettings() {
        guard let e = entity, context != nil else { return }
        e.serverAddress = serverSettings.serverAddress
        e.textLang = serverSettings.textLang
        e.refAudioPath = serverSettings.refAudioPath
        e.promptText = serverSettings.promptText
        e.promptLang = serverSettings.promptLang
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
