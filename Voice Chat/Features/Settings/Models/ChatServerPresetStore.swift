//
//  ChatServerPresetStore.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
import SwiftData

@MainActor
enum ChatServerPresetStore {
    static func fetch(from context: ModelContext) throws -> [ChatServerPreset] {
        let descriptor = FetchDescriptor<ChatServerPreset>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    static func apiFormatPreference(
        for presetID: UUID?,
        in presets: [ChatServerPreset]
    ) -> ChatAPIFormatPreference {
        guard let presetID,
              let preset = presets.first(where: { $0.id == presetID }) else {
            return .automatic
        }
        let raw = preset.apiFormatPreferenceRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ChatAPIFormatPreference(rawValue: raw) ?? .automatic
    }

    static func ensureDefaultIfNeeded(
        presets: inout [ChatServerPreset],
        appSettings: AppSettings,
        context: ModelContext,
        save: (String) -> Void
    ) -> UUID? {
        if presets.isEmpty {
            let fallback = ChatServerPreset(
                name: String(localized: "Default"),
                apiURL: appSettings.apiURL,
                selectedModel: appSettings.selectedModel
            )
            context.insert(fallback)
            save("insert default chat server preset")
            presets = [fallback]

            appSettings.selectedChatServerPresetID = fallback.id
            save("select default chat server preset")
            return fallback.id
        }

        if appSettings.selectedChatServerPresetID == nil {
            appSettings.selectedChatServerPresetID = presets.first?.id
            save("seed selectedChatServerPresetID")
        }
        return appSettings.selectedChatServerPresetID
    }

    static func validSelectionID(
        in presets: [ChatServerPreset],
        appSettings: AppSettings,
        save: (String) -> Void
    ) -> UUID? {
        guard !presets.isEmpty else { return nil }
        if let selected = appSettings.selectedChatServerPresetID,
           presets.contains(where: { $0.id == selected }) {
            return selected
        }

        let fallback = presets.first?.id
        appSettings.selectedChatServerPresetID = fallback
        save("repair selectedChatServerPresetID")
        return fallback
    }

    static func create(
        name: String,
        apiURL: String,
        selectedModel: String,
        apiFormatPreference: ChatAPIFormatPreference,
        context: ModelContext,
        save: (String) -> Void
    ) -> ChatServerPreset {
        let preset = ChatServerPreset(
            name: name,
            apiURL: apiURL,
            selectedModel: selectedModel,
            apiFormatPreferenceRaw: apiFormatPreference == .automatic ? nil : apiFormatPreference.rawValue
        )
        context.insert(preset)
        save("create chat server preset")
        return preset
    }

    static func delete(
        id: UUID,
        from presets: [ChatServerPreset],
        selectedID: inout UUID?,
        appSettings: AppSettings?,
        context: ModelContext,
        save: (String) -> Void
    ) -> Bool {
        guard let target = presets.first(where: { $0.id == id }) else { return false }

        if selectedID == id {
            let fallback = presets.first(where: { $0.id != id })?.id
            selectedID = fallback
            appSettings?.selectedChatServerPresetID = fallback
        }

        context.delete(target)
        save("delete chat server preset")
        return true
    }

    static func updateMetadata(
        id: UUID,
        name: String?,
        apiFormatPreference: ChatAPIFormatPreference?,
        in presets: [ChatServerPreset],
        save: (String) -> Void
    ) -> Bool {
        guard let preset = presets.first(where: { $0.id == id }) else { return false }
        let nextFormatRaw = apiFormatPreference.map {
            $0 == .automatic ? nil : $0.rawValue
        }
        let nameChanged = name.map { $0 != preset.name } ?? false
        let formatChanged = nextFormatRaw.map { $0 != preset.apiFormatPreferenceRaw } ?? false
        guard nameChanged || formatChanged else { return false }

        if let name { preset.name = name }
        if let apiFormatPreference {
            preset.apiFormatPreferenceRaw = apiFormatPreference == .automatic ? nil : apiFormatPreference.rawValue
        }
        preset.updatedAt = Date()
        save("update chat server preset meta")
        return true
    }

    static func updateSelectedSettings(
        apiURL: String,
        selectedModel: String,
        selectedID: UUID?,
        in presets: [ChatServerPreset],
        save: (String) -> Void
    ) -> Bool {
        guard let selectedID,
              let preset = presets.first(where: { $0.id == selectedID }) else {
            return false
        }
        guard preset.apiURL != apiURL || preset.selectedModel != selectedModel else {
            return false
        }
        preset.apiURL = apiURL
        preset.selectedModel = selectedModel
        preset.updatedAt = Date()
        save("update chat server preset")
        return true
    }

    static func touchAPIKey(
        selectedID: UUID?,
        in presets: [ChatServerPreset],
        save: (String) -> Void
    ) -> Bool {
        guard let selectedID,
              let preset = presets.first(where: { $0.id == selectedID }) else {
            return false
        }
        preset.updatedAt = Date()
        save("touch chat server preset api key")
        return true
    }
}
