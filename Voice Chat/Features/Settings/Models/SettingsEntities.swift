//
//  SettingsModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation
import SwiftData

// MARK: - Value Types (lightweight structures used by the UI)

struct ServerSettings: Codable, Equatable {
    var serverAddress: String
    var textLang: String
}

struct ModelSettings: Codable, Equatable {
    var modelId: String
    var language: String
    var autoSplit: String
}

struct ChatSettings: Codable, Equatable {
    var apiURL: String
    var selectedModel: String
    var apiKey: String
}

struct VoiceSettings: Codable, Equatable {
    var enableStreaming: Bool
}

// MARK: - Preset Entity (SwiftData)

@Model
final class VoicePreset {
    var id: UUID
    var name: String

    // Consolidated fields originally scattered across `ServerSettings` plus weight paths.
    var refAudioPath: String
    var promptText: String
    var promptLang: String
    var gptWeightsPath: String
    var sovitsWeightsPath: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        refAudioPath: String = "",
        promptText: String = "",
        promptLang: String = "auto",
        gptWeightsPath: String = "",
        sovitsWeightsPath: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.refAudioPath = refAudioPath
        self.promptText = promptText
        self.promptLang = promptLang
        self.gptWeightsPath = gptWeightsPath
        self.sovitsWeightsPath = sovitsWeightsPath
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Chat Server Preset Entity (SwiftData)

@Model
final class ChatServerPreset {
    var id: UUID
    var name: String

    var apiURL: String
    var selectedModel: String
    var apiFormatPreferenceRaw: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        apiURL: String = "",
        selectedModel: String = "",
        apiFormatPreferenceRaw: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.apiURL = apiURL
        self.selectedModel = selectedModel
        self.apiFormatPreferenceRaw = apiFormatPreferenceRaw
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Voice Server Preset Entity (SwiftData)

@Model
final class VoiceServerPreset {
    var id: UUID
    var name: String

    var serverAddress: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        serverAddress: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.serverAddress = serverAddress
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - System Prompt Preset Entity (SwiftData)

@Model
final class SystemPromptPreset {
    var id: UUID
    var name: String

    /// Which mode this preset belongs to ("normal" / "voice").
    /// Nil means the preset was created before mode separation was introduced.
    var mode: String?

    /// Prompt used for normal (text) chat requests.
    var normalPrompt: String
    /// Prompt used for voice (realtime) chat requests.
    var voicePrompt: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        mode: String? = nil,
        normalPrompt: String = "",
        voicePrompt: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.mode = mode
        self.normalPrompt = normalPrompt
        self.voicePrompt = voicePrompt
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - SwiftData Entity (single-row table storing global settings)

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
        modelImageInputOverrideJSON: String? = nil
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
    }
}
