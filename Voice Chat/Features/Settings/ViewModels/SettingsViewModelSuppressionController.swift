//
//  SettingsViewModelSuppressionController.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation

@MainActor
final class SettingsViewModelSuppressionController {
    enum Flag: Hashable {
        case autoSaves
        case voiceServerPresetDidSet
        case saveVoiceServerPreset
        case chatServerPresetDidSet
        case saveChatServerPreset
        case saveChatServerPresetFormat
        case voicePresetDidSet
        case saveVoicePreset
        case normalSystemPromptDidSet
        case saveNormalSystemPrompt
        case voiceSystemPromptDidSet
        case saveVoiceSystemPrompt
    }

    private var activeCounts: [Flag: Int] = [:]

    func isActive(_ flag: Flag) -> Bool {
        activeCounts[flag, default: 0] > 0
    }

    func withSuppressed(_ flag: Flag, perform body: () -> Void) {
        withSuppressed([flag], perform: body)
    }

    func withSuppressed(_ flags: [Flag], perform body: () -> Void) {
        for flag in flags {
            activeCounts[flag, default: 0] += 1
        }
        defer {
            for flag in flags {
                let nextCount = activeCounts[flag, default: 0] - 1
                if nextCount > 0 {
                    activeCounts[flag] = nextCount
                } else {
                    activeCounts.removeValue(forKey: flag)
                }
            }
        }
        body()
    }
}
