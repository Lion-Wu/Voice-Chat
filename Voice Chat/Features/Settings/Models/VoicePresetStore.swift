//
//  VoicePresetStore.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
import SwiftData

@MainActor
enum VoicePresetStore {
    static func fetch(from context: ModelContext) -> [VoicePreset] {
        let descriptor = FetchDescriptor<VoicePreset>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            print("SwiftData fetch VoicePreset failed: \(error)")
            return []
        }
    }

    static func ensureDefaultIfNeeded(
        presets: inout [VoicePreset],
        appSettings: AppSettings,
        promptLang: String,
        context: ModelContext,
        save: (String) -> Void
    ) -> UUID? {
        if presets.isEmpty {
            let fallback = makePreset(name: String(localized: "Default"), promptLang: promptLang)
            context.insert(fallback)
            save("insert default voice preset")
            presets = [fallback]

            appSettings.selectedPresetID = fallback.id
            save("select default voice preset")
            return fallback.id
        }

        if appSettings.selectedPresetID == nil {
            appSettings.selectedPresetID = presets.first?.id
            save("seed selectedPresetID")
        }
        return appSettings.selectedPresetID
    }

    static func validSelectionID(
        in presets: [VoicePreset],
        appSettings: AppSettings,
        save: (String) -> Void
    ) -> UUID? {
        guard !presets.isEmpty else { return nil }
        if let selected = appSettings.selectedPresetID,
           presets.contains(where: { $0.id == selected }) {
            return selected
        }

        let fallback = presets.first?.id
        appSettings.selectedPresetID = fallback
        save("repair selectedPresetID")
        return fallback
    }

    static func create(
        name: String,
        promptLang: String,
        context: ModelContext,
        save: (String) -> Void
    ) -> VoicePreset {
        let preset = makePreset(name: name, promptLang: promptLang)
        context.insert(preset)
        save("create preset")
        return preset
    }

    static func delete(
        id: UUID,
        from presets: [VoicePreset],
        selectedID: inout UUID?,
        appSettings: AppSettings?,
        context: ModelContext,
        save: (String) -> Void
    ) -> Bool {
        guard let target = presets.first(where: { $0.id == id }) else { return false }

        if selectedID == id {
            let fallback = presets.first(where: { $0.id != id })?.id
            selectedID = fallback
            appSettings?.selectedPresetID = fallback
        }

        context.delete(target)
        save("delete preset")
        return true
    }

    static func update(
        id: UUID,
        name: String?,
        refAudioPath: String?,
        promptText: String?,
        promptLang: String?,
        gptWeightsPath: String?,
        sovitsWeightsPath: String?,
        in presets: [VoicePreset],
        save: (String) -> Void
    ) -> Bool {
        guard let preset = presets.first(where: { $0.id == id }) else { return false }
        if let name { preset.name = name }
        if let refAudioPath { preset.refAudioPath = refAudioPath }
        if let promptText { preset.promptText = promptText }
        if let promptLang { preset.promptLang = promptLang }
        if let gptWeightsPath { preset.gptWeightsPath = gptWeightsPath }
        if let sovitsWeightsPath { preset.sovitsWeightsPath = sovitsWeightsPath }
        preset.updatedAt = Date()
        save("update preset")
        return true
    }

    private static func makePreset(name: String, promptLang: String) -> VoicePreset {
        VoicePreset(
            name: name,
            refAudioPath: "",
            promptText: "",
            promptLang: promptLang,
            gptWeightsPath: "",
            sovitsWeightsPath: ""
        )
    }
}
