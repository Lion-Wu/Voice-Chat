//
//  SystemPromptPresetStore.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
import SwiftData

struct SystemPromptPresetSelectionRepair: Equatable {
    let normalID: UUID
    let voiceID: UUID
    let didRepairPersistedSelection: Bool
}

enum SystemPromptPresetStore {
    static let normalMode = "normal"
    static let voiceMode = "voice"

    static func normalPresets(from presets: [SystemPromptPreset]) -> [SystemPromptPreset] {
        presets.filter { $0.mode == normalMode }
    }

    static func voicePresets(from presets: [SystemPromptPreset]) -> [SystemPromptPreset] {
        presets.filter { $0.mode == voiceMode }
    }

    static func selectedPreset(in presets: [SystemPromptPreset], id: UUID?) -> SystemPromptPreset? {
        presets.first { $0.id == id }
    }

    @MainActor
    static func fetch(from context: ModelContext) throws -> [SystemPromptPreset] {
        let descriptor = FetchDescriptor<SystemPromptPreset>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    @MainActor
    static func ensureDefaultsIfNeeded(
        presets: inout [SystemPromptPreset],
        context: ModelContext,
        save: (String) -> Void
    ) {
        let missingDefaults = missingDefaultPresets(for: presets)
        guard !missingDefaults.isEmpty else { return }

        missingDefaults.forEach { context.insert($0) }
        save("ensure default system prompt presets")
        presets.append(contentsOf: missingDefaults)
        presets.sort { $0.updatedAt > $1.updatedAt }
    }

    static func missingDefaultPresets(for presets: [SystemPromptPreset]) -> [SystemPromptPreset] {
        var defaults: [SystemPromptPreset] = []
        if normalPresets(from: presets).isEmpty {
            defaults.append(defaultPreset(mode: normalMode))
        }
        if voicePresets(from: presets).isEmpty {
            defaults.append(defaultPreset(mode: voiceMode))
        }
        return defaults
    }

    static func repairedSelection(
        in presets: [SystemPromptPreset],
        selectedNormalID: UUID?,
        persistedNormalID: UUID?,
        selectedVoiceID: UUID?,
        persistedVoiceID: UUID?
    ) -> SystemPromptPresetSelectionRepair? {
        guard let normalFallback = normalPresets(from: presets).first?.id else { return nil }
        guard let voiceFallback = voicePresets(from: presets).first?.id else { return nil }

        let byID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
        var didRepair = false

        let normalCandidate = selectedNormalID ?? persistedNormalID
        let normalID: UUID
        if let normalCandidate,
           let preset = byID[normalCandidate],
           preset.mode == normalMode {
            normalID = normalCandidate
        } else {
            normalID = normalFallback
            didRepair = true
        }

        let voiceCandidate = selectedVoiceID ?? persistedVoiceID
        let voiceID: UUID
        if let voiceCandidate,
           let preset = byID[voiceCandidate],
           preset.mode == voiceMode {
            voiceID = voiceCandidate
        } else {
            voiceID = voiceFallback
            didRepair = true
        }

        return SystemPromptPresetSelectionRepair(
            normalID: normalID,
            voiceID: voiceID,
            didRepairPersistedSelection: didRepair
        )
    }

    static func makePreset(mode: String, name: String) -> SystemPromptPreset {
        SystemPromptPreset(name: name, mode: mode, normalPrompt: "", voicePrompt: "")
    }

    @MainActor
    static func create(
        mode: String,
        name: String,
        context: ModelContext,
        save: (String) -> Void
    ) -> SystemPromptPreset {
        let preset = makePreset(mode: mode, name: name)
        context.insert(preset)
        save("create system prompt preset")
        return preset
    }

    @MainActor
    static func delete(
        id: UUID,
        from presets: [SystemPromptPreset],
        context: ModelContext,
        save: (String) -> Void
    ) -> Bool {
        guard let target = presets.first(where: { $0.id == id }) else { return false }
        context.delete(target)
        save("delete system prompt preset")
        return true
    }

    static func updateNormalPreset(_ preset: SystemPromptPreset, name: String?, prompt: String?) {
        preset.mode = normalMode
        if let name { preset.name = name }
        if let prompt { preset.normalPrompt = prompt }
        preset.voicePrompt = ""
        preset.updatedAt = Date()
    }

    static func updateNormalPreset(
        id: UUID,
        name: String?,
        prompt: String?,
        in presets: [SystemPromptPreset],
        save: (String) -> Void
    ) -> Bool {
        guard let preset = presets.first(where: { $0.id == id }) else { return false }
        let changed = preset.mode != normalMode
            || (name.map { $0 != preset.name } ?? false)
            || (prompt.map { $0 != preset.normalPrompt } ?? false)
            || !preset.voicePrompt.isEmpty
        guard changed else { return false }
        updateNormalPreset(preset, name: name, prompt: prompt)
        save("update normal system prompt preset")
        return true
    }

    static func updateVoicePreset(_ preset: SystemPromptPreset, name: String?, prompt: String?) {
        preset.mode = voiceMode
        if let name { preset.name = name }
        if let prompt { preset.voicePrompt = prompt }
        preset.normalPrompt = ""
        preset.updatedAt = Date()
    }

    static func updateVoicePreset(
        id: UUID,
        name: String?,
        prompt: String?,
        in presets: [SystemPromptPreset],
        save: (String) -> Void
    ) -> Bool {
        guard let preset = presets.first(where: { $0.id == id }) else { return false }
        let changed = preset.mode != voiceMode
            || (name.map { $0 != preset.name } ?? false)
            || (prompt.map { $0 != preset.voicePrompt } ?? false)
            || !preset.normalPrompt.isEmpty
        guard changed else { return false }
        updateVoicePreset(preset, name: name, prompt: prompt)
        save("update voice system prompt preset")
        return true
    }

    static func updatePreset(
        _ preset: SystemPromptPreset,
        name: String?,
        normalPrompt: String?,
        voicePrompt: String?
    ) {
        if let name { preset.name = name }
        if let normalPrompt { preset.normalPrompt = normalPrompt }
        if let voicePrompt { preset.voicePrompt = voicePrompt }
        preset.updatedAt = Date()
    }

    static func updatePreset(
        id: UUID,
        name: String?,
        normalPrompt: String?,
        voicePrompt: String?,
        in presets: [SystemPromptPreset],
        save: (String) -> Void
    ) -> Bool {
        guard let preset = presets.first(where: { $0.id == id }) else { return false }
        let changed = (name.map { $0 != preset.name } ?? false)
            || (normalPrompt.map { $0 != preset.normalPrompt } ?? false)
            || (voicePrompt.map { $0 != preset.voicePrompt } ?? false)
        guard changed else { return false }
        updatePreset(
            preset,
            name: name,
            normalPrompt: normalPrompt,
            voicePrompt: voicePrompt
        )
        save("update system prompt preset")
        return true
    }

    private static func defaultPreset(mode: String) -> SystemPromptPreset {
        SystemPromptPreset(
            name: String(localized: "Default"),
            mode: mode
        )
    }
}
