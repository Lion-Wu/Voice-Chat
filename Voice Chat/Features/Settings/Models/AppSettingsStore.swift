//
//  AppSettingsStore.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
import SwiftData

struct AppSettingsLoadedState: Equatable {
    let serverSettings: ServerSettings
    let modelSettings: ModelSettings
    let chatSettings: ChatSettings
    let voiceSettings: VoiceSettings
    let developerModeEnabled: Bool
    let hapticFeedbackEnabled: Bool
    let apiAdvancedSettings: APIAdvancedSettings
    let toolUseSettings: ToolUseSettings
    let selectedVoiceServerPresetID: UUID?
    let selectedChatServerPresetID: UUID?
    let selectedPresetID: UUID?
    let selectedNormalSystemPromptPresetID: UUID?
    let selectedVoiceSystemPromptPresetID: UUID?
    let modelImageInputOverrides: [String: Bool]
}

@MainActor
enum AppSettingsStore {
    static func loadOrCreate(in context: ModelContext) throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>(predicate: nil, sortBy: [])
        let fetched = try context.fetch(descriptor)
        if fetched.isEmpty {
            let fresh = AppSettings()
            context.insert(fresh)
            return fresh
        }

        let sorted = fetched.sorted { lhs, rhs in
            lhs.id.uuidString < rhs.id.uuidString
        }
        for other in sorted.dropFirst() {
            context.delete(other)
        }
        return sorted[0]
    }

    static func loadedState(
        from settings: AppSettings,
        chatAPIKey: String,
        defaultHapticFeedbackEnabled: Bool,
        defaultAPIAdvancedSettings: APIAdvancedSettings
    ) -> AppSettingsLoadedState {
        AppSettingsLoadedState(
            serverSettings: ServerSettings(
                serverAddress: settings.serverAddress,
                textLang: settings.textLang
            ),
            modelSettings: ModelSettings(
                modelId: settings.modelId,
                language: settings.language,
                autoSplit: settings.autoSplit
            ),
            chatSettings: ChatSettings(
                apiURL: settings.apiURL,
                selectedModel: settings.selectedModel,
                apiKey: chatAPIKey
            ),
            voiceSettings: VoiceSettings(
                enableStreaming: settings.enableStreaming,
                provider: TTSProvider(rawValue: settings.ttsProviderRawValue ?? "") ?? .gptSoVITS,
                appleSpeechVoiceIdentifier: settings.appleSpeechVoiceIdentifier,
                personalVoiceIdentifier: settings.personalVoiceIdentifier
            ),
            developerModeEnabled: settings.developerModeEnabled ?? false,
            hapticFeedbackEnabled: settings.hapticFeedbackEnabled ?? defaultHapticFeedbackEnabled,
            apiAdvancedSettings: APIAdvancedSettingsCodec.decode(
                from: settings.apiAdvancedSettingsJSON,
                fallback: defaultAPIAdvancedSettings
            ),
            toolUseSettings: ToolUseSettingsCodec.decode(from: settings.toolUseSettingsJSON),
            selectedVoiceServerPresetID: settings.selectedVoiceServerPresetID,
            selectedChatServerPresetID: settings.selectedChatServerPresetID,
            selectedPresetID: settings.selectedPresetID,
            selectedNormalSystemPromptPresetID: settings.selectedNormalSystemPromptPresetID,
            selectedVoiceSystemPromptPresetID: settings.selectedVoiceSystemPromptPresetID,
            modelImageInputOverrides: ChatModelCapabilityStore.decodeImageInputOverrides(
                from: settings.modelImageInputOverrideJSON
            )
        )
    }

    static func backfillMissingValues(
        in settings: AppSettings,
        loadedState: AppSettingsLoadedState,
        save: (String) -> Void
    ) {
        if settings.hapticFeedbackEnabled == nil {
            settings.hapticFeedbackEnabled = loadedState.hapticFeedbackEnabled
            save("backfill haptic feedback setting")
        }
        if settings.apiAdvancedSettingsJSON == nil {
            settings.apiAdvancedSettingsJSON = APIAdvancedSettingsCodec.encode(loadedState.apiAdvancedSettings)
            save("backfill API advanced settings")
        }
        if settings.toolUseSettingsJSON == nil {
            settings.toolUseSettingsJSON = ToolUseSettingsCodec.encode(loadedState.toolUseSettings)
            save("backfill tool-use settings")
        }
        if settings.ttsProviderRawValue == nil {
            settings.ttsProviderRawValue = loadedState.voiceSettings.provider.rawValue
            save("backfill TTS provider setting")
        }
    }
}
