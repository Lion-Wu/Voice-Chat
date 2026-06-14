//
//  SettingsPresetMutationController.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation
import SwiftData

@MainActor
enum SettingsPresetMutationController {
    static func createVoiceServerPreset(
        name: String,
        serverAddress: String,
        context: ModelContext,
        save: (String) -> Void
    ) -> VoiceServerPreset {
        VoiceServerPresetStore.create(
            name: name,
            serverAddress: serverAddress,
            context: context,
            save: save
        )
    }

    static func deleteVoiceServerPreset(
        id: UUID,
        presets: [VoiceServerPreset],
        selectedID: inout UUID?,
        appSettings: AppSettings?,
        context: ModelContext,
        save: (String) -> Void
    ) -> Bool {
        VoiceServerPresetStore.delete(
            id: id,
            from: presets,
            selectedID: &selectedID,
            appSettings: appSettings,
            context: context,
            save: save
        )
    }

    static func updateVoiceServerPreset(
        id: UUID,
        name: String?,
        presets: [VoiceServerPreset],
        save: (String) -> Void
    ) -> Bool {
        VoiceServerPresetStore.updateName(
            id: id,
            name: name,
            in: presets,
            save: save
        )
    }

    static func selectVoiceServerPreset(
        id: UUID?,
        selectedID: inout UUID?,
        appSettings: AppSettings,
        save: (String) -> Void
    ) -> Bool {
        guard selectedID != id else { return false }
        selectedID = id
        appSettings.selectedVoiceServerPresetID = id
        save("select voice server preset")
        return true
    }

    static func createChatServerPreset(
        name: String,
        apiURL: String,
        selectedModel: String,
        apiFormatPreference: ChatAPIFormatPreference,
        apiKey: String,
        context: ModelContext,
        saveAPIKey: (String, UUID) -> Void,
        save: (String) -> Void
    ) -> ChatServerPreset {
        let preset = ChatServerPresetStore.create(
            name: name,
            apiURL: apiURL,
            selectedModel: selectedModel,
            apiFormatPreference: apiFormatPreference,
            context: context,
            save: save
        )
        saveAPIKey(apiKey, preset.id)
        return preset
    }

    static func deleteChatServerPreset(
        id: UUID,
        presets: [ChatServerPreset],
        selectedID: inout UUID?,
        appSettings: AppSettings?,
        context: ModelContext,
        deleteAPIKey: (UUID) -> Void,
        save: (String) -> Void
    ) -> Bool {
        guard ChatServerPresetStore.delete(
            id: id,
            from: presets,
            selectedID: &selectedID,
            appSettings: appSettings,
            context: context,
            save: save
        ) else {
            return false
        }
        deleteAPIKey(id)
        return true
    }

    static func updateChatServerPreset(
        id: UUID,
        name: String?,
        apiFormatPreference: ChatAPIFormatPreference?,
        presets: [ChatServerPreset],
        save: (String) -> Void
    ) -> Bool {
        ChatServerPresetStore.updateMetadata(
            id: id,
            name: name,
            apiFormatPreference: apiFormatPreference,
            in: presets,
            save: save
        )
    }

    static func selectChatServerPreset(
        id: UUID?,
        selectedID: inout UUID?,
        appSettings: AppSettings,
        save: (String) -> Void
    ) -> Bool {
        guard selectedID != id else { return false }
        selectedID = id
        appSettings.selectedChatServerPresetID = id
        save("select chat server preset")
        return true
    }

    static func createVoicePreset(
        name: String,
        promptLang: String,
        context: ModelContext,
        save: (String) -> Void
    ) -> VoicePreset {
        VoicePresetStore.create(
            name: name,
            promptLang: promptLang,
            context: context,
            save: save
        )
    }

    static func deleteVoicePreset(
        id: UUID,
        presets: [VoicePreset],
        selectedID: inout UUID?,
        appSettings: AppSettings?,
        context: ModelContext,
        save: (String) -> Void
    ) -> Bool {
        VoicePresetStore.delete(
            id: id,
            from: presets,
            selectedID: &selectedID,
            appSettings: appSettings,
            context: context,
            save: save
        )
    }

    static func updateVoicePreset(
        id: UUID,
        name: String?,
        refAudioPath: String?,
        promptText: String?,
        promptLang: String?,
        gptWeightsPath: String?,
        sovitsWeightsPath: String?,
        presets: [VoicePreset],
        save: (String) -> Void
    ) -> Bool {
        VoicePresetStore.update(
            id: id,
            name: name,
            refAudioPath: refAudioPath,
            promptText: promptText,
            promptLang: promptLang,
            gptWeightsPath: gptWeightsPath,
            sovitsWeightsPath: sovitsWeightsPath,
            in: presets,
            save: save
        )
    }

    static func selectVoicePreset(
        id: UUID?,
        selectedID: inout UUID?,
        appSettings: AppSettings,
        save: (String) -> Void
    ) -> Bool {
        guard selectedID != id else { return false }
        selectedID = id
        appSettings.selectedPresetID = id
        save("select preset")
        return true
    }

    static func createSystemPromptPreset(
        mode: String,
        name: String,
        context: ModelContext,
        save: (String) -> Void
    ) -> SystemPromptPreset {
        SystemPromptPresetStore.create(
            mode: mode,
            name: name,
            context: context,
            save: save
        )
    }

    static func deleteSystemPromptPreset(
        id: UUID,
        presets: [SystemPromptPreset],
        context: ModelContext,
        save: (String) -> Void
    ) -> Bool {
        SystemPromptPresetStore.delete(
            id: id,
            from: presets,
            context: context,
            save: save
        )
    }

    static func updateNormalSystemPromptPreset(
        id: UUID,
        name: String?,
        prompt: String?,
        presets: [SystemPromptPreset],
        save: (String) -> Void
    ) -> Bool {
        SystemPromptPresetStore.updateNormalPreset(
            id: id,
            name: name,
            prompt: prompt,
            in: presets,
            save: save
        )
    }

    static func updateVoiceSystemPromptPreset(
        id: UUID,
        name: String?,
        prompt: String?,
        presets: [SystemPromptPreset],
        save: (String) -> Void
    ) -> Bool {
        SystemPromptPresetStore.updateVoicePreset(
            id: id,
            name: name,
            prompt: prompt,
            in: presets,
            save: save
        )
    }

    static func updateSystemPromptPreset(
        id: UUID,
        name: String?,
        normalPrompt: String?,
        voicePrompt: String?,
        presets: [SystemPromptPreset],
        save: (String) -> Void
    ) -> Bool {
        SystemPromptPresetStore.updatePreset(
            id: id,
            name: name,
            normalPrompt: normalPrompt,
            voicePrompt: voicePrompt,
            in: presets,
            save: save
        )
    }

    static func selectNormalSystemPromptPreset(
        id: UUID?,
        selectedID: inout UUID?,
        appSettings: AppSettings,
        save: (String) -> Void
    ) -> Bool {
        guard selectedID != id else { return false }
        selectedID = id
        appSettings.selectedNormalSystemPromptPresetID = id
        save("select normal system prompt preset")
        return true
    }

    static func selectVoiceSystemPromptPreset(
        id: UUID?,
        selectedID: inout UUID?,
        appSettings: AppSettings,
        save: (String) -> Void
    ) -> Bool {
        guard selectedID != id else { return false }
        selectedID = id
        appSettings.selectedVoiceSystemPromptPresetID = id
        save("select voice system prompt preset")
        return true
    }
}
