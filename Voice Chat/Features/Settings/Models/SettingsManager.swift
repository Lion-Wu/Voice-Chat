//
//  SettingsManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation
import SwiftData

// MARK: - Settings Manager (SwiftData-backed)

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // Global settings state.
    @Published var serverSettings: ServerSettings
    @Published var modelSettings: ModelSettings
    @Published var chatSettings: ChatSettings
    @Published var chatModelCapabilityStore: ChatModelCapabilityStore
    @Published var voiceSettings: VoiceSettings
    @Published var developerModeEnabled: Bool
    @Published var hapticFeedbackEnabled: Bool
    @Published var apiAdvancedSettings: APIAdvancedSettings
    @Published var toolUseSettings: ToolUseSettings

    lazy var chatModelCapabilities = makeChatModelCapabilityController()

    // Voice server preset list and selection state.
    @Published var voiceServerPresets: [VoiceServerPreset] = []
    @Published var selectedVoiceServerPresetID: UUID?

    // Chat server preset list and selection state.
    @Published var chatServerPresets: [ChatServerPreset] = []
    @Published var selectedChatServerPresetID: UUID?

    // Preset list and selection state.
    @Published var presets: [VoicePreset] = []
    @Published var selectedPresetID: UUID?

    // System prompt preset list and selection state.
    @Published var systemPromptPresets: [SystemPromptPreset] = []
    @Published var selectedNormalSystemPromptPresetID: UUID?
    @Published var selectedVoiceSystemPromptPresetID: UUID?

    @Published var presetApplyStatus: TTSPresetApplyStatus = .idle

    let persistence = SettingsPersistenceController()
    var pendingDeveloperModeEnabled: Bool?
    var pendingHapticFeedbackEnabled: Bool?
    var pendingAPIAdvancedSettings: APIAdvancedSettings?
    var pendingToolUseSettings: ToolUseSettings?
    let chatAPIKeyStore = ChatAPIKeyStore()
    let chatModelCatalogRefreshCoordinator = ChatModelCatalogRefreshCoordinator()
    let presetApplyController = SettingsPresetApplyController()
    var onPersistentStoreReadFailure: ((Error) -> Void)?
    var isCoalescingPersistenceWrites = false

    // Used to gate one-time work performed at launch.
    var didPrefetchChatModelsOnLaunch = false

    private init() {
        // Initialise with defaults until `attach(context:)` loads persisted data.
        self.serverSettings = ServerSettings(
            serverAddress: SettingsDefaults.serverAddress,
            textLang: SettingsDefaults.textLang
        )
        self.modelSettings = ModelSettings(modelId: "", language: SettingsDefaults.modelLanguage, autoSplit: SettingsDefaults.autoSplit)
        self.chatSettings = ChatSettings(apiURL: SettingsDefaults.apiURL, selectedModel: "", apiKey: "")
        self.chatModelCapabilityStore = ChatModelCapabilityStore(
            thinkingPreferences: ChatModelCapabilityStore.decodeThinkingPreferences()
        )
        self.voiceSettings = VoiceSettings(
            enableStreaming: SettingsDefaults.enableStreaming,
            provider: .gptSoVITS,
            appleSpeechVoiceIdentifier: nil,
            personalVoiceIdentifier: nil
        )
        self.developerModeEnabled = SettingsDefaults.developerModeEnabled
        self.hapticFeedbackEnabled = SettingsDefaults.hapticFeedbackEnabled
        self.apiAdvancedSettings = SettingsDefaults.apiAdvancedSettings
        self.toolUseSettings = ToolUseSettings.defaults

        bindPresetApplyStatusUpdates()
    }

}
