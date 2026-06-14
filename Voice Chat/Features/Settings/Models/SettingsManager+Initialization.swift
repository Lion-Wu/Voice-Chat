//
//  SettingsManager+Initialization.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/14.
//

import Foundation

extension SettingsManager {
    func bindPresetApplyStatusUpdates() {
        presetApplyController.onStatusChange = { [weak self] status in
            self?.presetApplyStatus = status
        }
    }

    func makeChatModelCapabilityController() -> SettingsChatModelCapabilityController {
        SettingsChatModelCapabilityController(
            getStore: { [unowned self] in chatModelCapabilityStore },
            setStore: { [unowned self] in chatModelCapabilityStore = $0 },
            context: { [unowned self] in
                SettingsChatModelCapabilityContext(
                    chatSettings: chatSettings,
                    chatServerPresets: chatServerPresets,
                    selectedChatServerPresetID: selectedChatServerPresetID
                )
            },
            saveImageInputOverrides: { [unowned self] in
                saveChatModelImageInputOverrides()
            }
        )
    }
}
