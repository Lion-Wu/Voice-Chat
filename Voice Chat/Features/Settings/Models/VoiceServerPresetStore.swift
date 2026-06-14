//
//  VoiceServerPresetStore.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
import SwiftData

@MainActor
enum VoiceServerPresetStore {
    static func fetch(from context: ModelContext) -> [VoiceServerPreset] {
        let descriptor = FetchDescriptor<VoiceServerPreset>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            print("SwiftData fetch VoiceServerPreset failed: \(error)")
            return []
        }
    }

    static func ensureDefaultIfNeeded(
        presets: inout [VoiceServerPreset],
        appSettings: AppSettings,
        context: ModelContext,
        save: (String) -> Void
    ) -> UUID? {
        if presets.isEmpty {
            let fallback = VoiceServerPreset(
                name: String(localized: "Default"),
                serverAddress: appSettings.serverAddress
            )
            context.insert(fallback)
            save("insert default voice server preset")
            presets = [fallback]

            appSettings.selectedVoiceServerPresetID = fallback.id
            save("select default voice server preset")
            return fallback.id
        }

        if appSettings.selectedVoiceServerPresetID == nil {
            appSettings.selectedVoiceServerPresetID = presets.first?.id
            save("seed selectedVoiceServerPresetID")
        }
        return appSettings.selectedVoiceServerPresetID
    }

    static func validSelectionID(
        in presets: [VoiceServerPreset],
        appSettings: AppSettings,
        save: (String) -> Void
    ) -> UUID? {
        guard !presets.isEmpty else { return nil }
        if let selected = appSettings.selectedVoiceServerPresetID,
           presets.contains(where: { $0.id == selected }) {
            return selected
        }

        let fallback = presets.first?.id
        appSettings.selectedVoiceServerPresetID = fallback
        save("repair selectedVoiceServerPresetID")
        return fallback
    }

    static func create(
        name: String,
        serverAddress: String,
        context: ModelContext,
        save: (String) -> Void
    ) -> VoiceServerPreset {
        let preset = VoiceServerPreset(name: name, serverAddress: serverAddress)
        context.insert(preset)
        save("create voice server preset")
        return preset
    }

    static func delete(
        id: UUID,
        from presets: [VoiceServerPreset],
        selectedID: inout UUID?,
        appSettings: AppSettings?,
        context: ModelContext,
        save: (String) -> Void
    ) -> Bool {
        guard let target = presets.first(where: { $0.id == id }) else { return false }

        if selectedID == id {
            let fallback = presets.first(where: { $0.id != id })?.id
            selectedID = fallback
            appSettings?.selectedVoiceServerPresetID = fallback
        }

        context.delete(target)
        save("delete voice server preset")
        return true
    }

    static func updateName(
        id: UUID,
        name: String?,
        in presets: [VoiceServerPreset],
        save: (String) -> Void
    ) -> Bool {
        guard let preset = presets.first(where: { $0.id == id }) else { return false }
        if let name { preset.name = name }
        preset.updatedAt = Date()
        save("update voice server preset meta")
        return true
    }

    static func updateSelectedServerAddress(
        _ serverAddress: String,
        selectedID: UUID?,
        in presets: [VoiceServerPreset],
        save: (String) -> Void
    ) -> Bool {
        guard let selectedID,
              let preset = presets.first(where: { $0.id == selectedID }) else {
            return false
        }

        let next = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = preset.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard next != current else { return false }

        preset.serverAddress = serverAddress
        preset.updatedAt = Date()
        save("update voice server preset")
        return true
    }
}
