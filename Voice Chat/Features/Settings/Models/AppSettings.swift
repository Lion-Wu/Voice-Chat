//
//  AppSettings.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
import SwiftData

@Model
final class AppSettings {
    var id: UUID
    var serverAddress: String
    var textLang: String

    var modelId: String
    var language: String
    var autoSplit: String

    var apiURL: String
    var selectedModel: String
    var selectedChatServerPresetID: UUID?
    var selectedVoiceServerPresetID: UUID?

    var enableStreaming: Bool
    var developerModeEnabled: Bool?
    var hapticFeedbackEnabled: Bool?

    // Currently selected preset identifier (optional when nothing is selected).
    var selectedPresetID: UUID?

    // Separate selections for normal/voice chat modes.
    var selectedNormalSystemPromptPresetID: UUID?
    var selectedVoiceSystemPromptPresetID: UUID?
    var modelImageInputOverrideJSON: String?
    var apiAdvancedSettingsJSON: String?

    init(
        serverAddress: String = "http://localhost:9880",
        textLang: String = "auto",
        modelId: String = "",
        language: String = "auto",
        autoSplit: String = "cut0",
        apiURL: String = "http://localhost:1234",
        selectedModel: String = "",
        selectedChatServerPresetID: UUID? = nil,
        selectedVoiceServerPresetID: UUID? = nil,
        enableStreaming: Bool = true,
        developerModeEnabled: Bool = false,
        hapticFeedbackEnabled: Bool? = true,
        selectedPresetID: UUID? = nil,
        selectedNormalSystemPromptPresetID: UUID? = nil,
        selectedVoiceSystemPromptPresetID: UUID? = nil,
        modelImageInputOverrideJSON: String? = nil,
        apiAdvancedSettingsJSON: String? = nil
    ) {
        self.id = UUID()
        self.serverAddress = serverAddress
        self.textLang = textLang
        self.modelId = modelId
        self.language = language
        self.autoSplit = autoSplit
        self.apiURL = apiURL
        self.selectedModel = selectedModel
        self.selectedChatServerPresetID = selectedChatServerPresetID
        self.selectedVoiceServerPresetID = selectedVoiceServerPresetID
        self.enableStreaming = enableStreaming
        self.developerModeEnabled = developerModeEnabled
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.selectedPresetID = selectedPresetID
        self.selectedNormalSystemPromptPresetID = selectedNormalSystemPromptPresetID
        self.selectedVoiceSystemPromptPresetID = selectedVoiceSystemPromptPresetID
        self.modelImageInputOverrideJSON = modelImageInputOverrideJSON
        self.apiAdvancedSettingsJSON = apiAdvancedSettingsJSON
    }
}
