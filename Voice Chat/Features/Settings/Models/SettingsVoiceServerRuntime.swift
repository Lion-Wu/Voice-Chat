//
//  SettingsVoiceServerRuntime.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation
import SwiftData

@MainActor
enum SettingsVoiceServerRuntime {
    static func selectedPreset(
        in presets: [VoiceServerPreset],
        selectedID: UUID?
    ) -> VoiceServerPreset? {
        presets.first { $0.id == selectedID }
    }

    @discardableResult
    static func updateSettings(
        serverAddress: String,
        textLang: String,
        serverSettings: inout ServerSettings,
        presets: [VoiceServerPreset],
        selectedID: UUID?,
        hasContext: Bool,
        persistServerSettings: (ServerSettings) -> Void,
        save: (String) -> Void
    ) -> Bool {
        let nextSettings = ServerSettings(
            serverAddress: serverAddress,
            textLang: textLang
        )
        if nextSettings != serverSettings {
            serverSettings = nextSettings
            persistServerSettings(nextSettings)
        }

        guard hasContext else { return false }
        return VoiceServerPresetStore.updateSelectedServerAddress(
            serverAddress,
            selectedID: selectedID,
            in: presets,
            save: save
        )
    }

    static func createPreset(
        name: String,
        serverSettings: ServerSettings,
        context: ModelContext,
        save: (String) -> Void
    ) -> VoiceServerPreset {
        SettingsPresetMutationController.createVoiceServerPreset(
            name: name,
            serverAddress: serverSettings.serverAddress,
            context: context,
            save: save
        )
    }

    static func deletePreset(
        id: UUID,
        presets: [VoiceServerPreset],
        selectedID: inout UUID?,
        appSettings: AppSettings?,
        context: ModelContext,
        save: (String) -> Void
    ) -> Bool {
        SettingsPresetMutationController.deleteVoiceServerPreset(
            id: id,
            presets: presets,
            selectedID: &selectedID,
            appSettings: appSettings,
            context: context,
            save: save
        )
    }

    static func updatePreset(
        id: UUID,
        name: String?,
        presets: [VoiceServerPreset],
        save: (String) -> Void
    ) -> Bool {
        SettingsPresetMutationController.updateVoiceServerPreset(
            id: id,
            name: name,
            presets: presets,
            save: save
        )
    }

    static func selectPreset(
        id: UUID?,
        selectedID: inout UUID?,
        appSettings: AppSettings,
        presets: [VoiceServerPreset],
        serverSettings: inout ServerSettings,
        persistServerSettings: (ServerSettings) -> Void,
        save: (String) -> Void
    ) -> Bool {
        guard selectedID != id else { return false }
        selectedID = id
        appSettings.selectedVoiceServerPresetID = id

        if let preset = selectedPreset(in: presets, selectedID: id) {
            let nextSettings = ServerSettings(
                serverAddress: preset.serverAddress,
                textLang: serverSettings.textLang
            )
            if nextSettings != serverSettings {
                serverSettings = nextSettings
                persistServerSettings(nextSettings)
            }
        }
        save("select voice server preset")
        return true
    }

    @discardableResult
    static func applySelectedPresetToServerSettings(
        presets: [VoiceServerPreset],
        selectedID: UUID?,
        serverSettings: inout ServerSettings,
        persistServerSettings: (ServerSettings) -> Void
    ) -> Bool {
        guard let preset = selectedPreset(in: presets, selectedID: selectedID) else {
            return false
        }
        let nextSettings = ServerSettings(
            serverAddress: preset.serverAddress,
            textLang: serverSettings.textLang
        )
        guard nextSettings != serverSettings else { return false }
        serverSettings = nextSettings
        persistServerSettings(nextSettings)
        return true
    }
}
