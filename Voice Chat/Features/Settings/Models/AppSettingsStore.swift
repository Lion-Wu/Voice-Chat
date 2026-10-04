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
    let modelCapabilities: ChatModelCapabilityStore
}

@MainActor
enum AppSettingsStore {
    static func loadOrCreate(
        in context: ModelContext,
        defaultHapticFeedbackEnabled: Bool,
        defaultAPIAdvancedSettings: APIAdvancedSettings
    ) throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>(predicate: nil, sortBy: [])
        let fetched = try context.fetch(descriptor)
        if fetched.isEmpty {
            let fresh = AppSettings(
                hapticFeedbackEnabled: defaultHapticFeedbackEnabled,
                apiAdvancedSettingsJSON: APIAdvancedSettingsCodec.encode(defaultAPIAdvancedSettings)
            )
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
                provider: TTSProvider(rawValue: settings.ttsProviderRawValue) ?? .gptSoVITS,
                appleSpeechVoiceIdentifier: settings.appleSpeechVoiceIdentifier,
                personalVoiceIdentifier: settings.personalVoiceIdentifier
            ),
            developerModeEnabled: settings.developerModeEnabled,
            hapticFeedbackEnabled: settings.hapticFeedbackEnabled,
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
            modelCapabilities: ChatModelCapabilityStore.restoringPreferences(from: settings)
        )
    }

    // Damaged settings use explicit field and payload validation; normal exports
    // preserve the entire database without maintaining a second field list.
    nonisolated static func recover(_ row: RecoveryRow) throws -> AppSettings {
        let model = AppSettings()
        let defaultAdvancedSettings = APIAdvancedSettingsCodec.decode(from: model.apiAdvancedSettingsJSON, fallback: SettingsDefaults.apiAdvancedSettings)
        let defaultToolSettings = ToolUseSettingsCodec.decode(from: model.toolUseSettingsJSON)
        let defaultImageOverrides = ChatModelCapabilityStore.decodeImageInputOverrides(from: model.modelImageInputOverrideJSON)
        model.id = try row.value("id")
        model.serverAddress = row.recover("serverAddress", defaultValue: model.serverAddress)
        model.textLang = row.recover("textLang", defaultValue: model.textLang)
        model.modelId = row.recover("modelId", defaultValue: model.modelId)
        model.language = row.recover("language", defaultValue: model.language)
        model.autoSplit = row.recover("autoSplit", defaultValue: model.autoSplit)
        model.apiURL = row.recover("apiURL", defaultValue: model.apiURL)
        model.selectedModel = row.recover("selectedModel", defaultValue: model.selectedModel)
        model.selectedChatServerPresetID = row.recover("selectedChatServerPresetID", defaultValue: model.selectedChatServerPresetID)
        model.selectedVoiceServerPresetID = row.recover("selectedVoiceServerPresetID", defaultValue: model.selectedVoiceServerPresetID)
        model.enableStreaming = row.recover("enableStreaming", defaultValue: model.enableStreaming)
        model.ttsProviderRawValue = row.recover("ttsProviderRawValue", defaultValue: model.ttsProviderRawValue)
        model.appleSpeechVoiceIdentifier = row.recover("appleSpeechVoiceIdentifier", defaultValue: model.appleSpeechVoiceIdentifier)
        model.personalVoiceIdentifier = row.recover("personalVoiceIdentifier", defaultValue: model.personalVoiceIdentifier)
        model.developerModeEnabled = row.recover("developerModeEnabled", defaultValue: model.developerModeEnabled)
        model.hapticFeedbackEnabled = row.recover("hapticFeedbackEnabled", defaultValue: model.hapticFeedbackEnabled)
        model.selectedPresetID = row.recover("selectedPresetID", defaultValue: model.selectedPresetID)
        model.selectedNormalSystemPromptPresetID = row.recover("selectedNormalSystemPromptPresetID", defaultValue: model.selectedNormalSystemPromptPresetID)
        model.selectedVoiceSystemPromptPresetID = row.recover("selectedVoiceSystemPromptPresetID", defaultValue: model.selectedVoiceSystemPromptPresetID)
        model.modelThinkingPreferencesJSON = row.recover("modelThinkingPreferencesJSON", defaultValue: model.modelThinkingPreferencesJSON)
        model.detectedAPIFormatsJSON = row.recover("detectedAPIFormatsJSON", defaultValue: model.detectedAPIFormatsJSON)
        model.modelImageInputOverrideJSON = row.recover("modelImageInputOverrideJSON", defaultValue: model.modelImageInputOverrideJSON)
        model.apiAdvancedSettingsJSON = row.recover("apiAdvancedSettingsJSON", defaultValue: model.apiAdvancedSettingsJSON)
        model.toolUseSettingsJSON = row.recover("toolUseSettingsJSON", defaultValue: model.toolUseSettingsJSON)
        model.apiAdvancedSettingsJSON = try row.validJSON(
            model.apiAdvancedSettingsJSON, defaultValue: defaultAdvancedSettings
        )
        model.toolUseSettingsJSON = try row.validJSON(model.toolUseSettingsJSON, defaultValue: defaultToolSettings)
        model.modelImageInputOverrideJSON = try row.validJSON(model.modelImageInputOverrideJSON, defaultValue: defaultImageOverrides)
        if let value = model.modelThinkingPreferencesJSON {
            model.modelThinkingPreferencesJSON = try row.validJSON(value, defaultValue: [String: String]())
        }
        if let value = model.detectedAPIFormatsJSON {
            model.detectedAPIFormatsJSON = try row.validJSON(value, defaultValue: [String: [String: String]]())
        }
        return model
    }
}
