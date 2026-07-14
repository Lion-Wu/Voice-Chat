//
//  SettingsManager+StateAccess.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/14.
//

import Combine
import Foundation
import SwiftData

extension SettingsManager {
    var activeAPIAdvancedSettings: APIAdvancedSettings {
        DeveloperRuntimeSettingsPolicy.apiAdvancedSettings(
            configured: apiAdvancedSettings,
            developerModeEnabled: developerModeEnabled
        )
    }

    var activeToolUseSettings: ToolUseSettings {
        DeveloperRuntimeSettingsPolicy.toolUseSettings(
            configured: toolUseSettings,
            developerModeEnabled: developerModeEnabled
        )
    }

    var chatModelCapabilityChanges: AnyPublisher<ChatModelCapabilityStore, Never> {
        $chatModelCapabilityStore.eraseToAnyPublisher()
    }

    var selectedVoiceServerPreset: VoiceServerPreset? {
        SettingsVoiceServerRuntime.selectedPreset(
            in: voiceServerPresets,
            selectedID: selectedVoiceServerPresetID
        )
    }

    var selectedChatServerPreset: ChatServerPreset? {
        SettingsChatServerRuntime.selectedPreset(
            in: chatServerPresets,
            selectedID: selectedChatServerPresetID
        )
    }

    var selectedPreset: VoicePreset? {
        presets.first { $0.id == selectedPresetID }
    }

    var selectedNormalSystemPromptPreset: SystemPromptPreset? {
        SystemPromptPresetStore.selectedPreset(in: systemPromptPresets, id: selectedNormalSystemPromptPresetID)
    }

    var selectedVoiceSystemPromptPreset: SystemPromptPreset? {
        SystemPromptPresetStore.selectedPreset(in: systemPromptPresets, id: selectedVoiceSystemPromptPresetID)
    }

    var normalSystemPromptPresets: [SystemPromptPreset] {
        SystemPromptPresetStore.normalPresets(from: systemPromptPresets)
    }

    var voiceSystemPromptPresets: [SystemPromptPreset] {
        SystemPromptPresetStore.voicePresets(from: systemPromptPresets)
    }

    var isApplyingPreset: Bool { presetApplyStatus.isApplying }
    var isRetryingPresetApply: Bool { presetApplyStatus.isRetrying }
    var presetApplyRetryAttempt: Int { presetApplyStatus.retryAttempt }
    var presetApplyRetryLastError: String? { presetApplyStatus.retryLastError }
    var lastApplyError: String? { presetApplyStatus.lastError }
    var lastPresetApplyAt: Date? { presetApplyStatus.lastAppliedAt }
    var lastPresetApplySucceeded: Bool { presetApplyStatus.lastSucceeded }

    var context: ModelContext? { persistence.context }
    var entity: AppSettings? { persistence.entity }
}

enum DeveloperRuntimeSettingsPolicy {
    static func apiAdvancedSettings(
        configured: APIAdvancedSettings,
        developerModeEnabled: Bool
    ) -> APIAdvancedSettings {
        developerModeEnabled ? configured : SettingsDefaults.apiAdvancedSettings
    }

    static func toolUseSettings(
        configured: ToolUseSettings,
        developerModeEnabled: Bool
    ) -> ToolUseSettings {
        developerModeEnabled
            ? configured
            : configured.resettingDeveloperRequestPolicyToDefaults()
    }
}
