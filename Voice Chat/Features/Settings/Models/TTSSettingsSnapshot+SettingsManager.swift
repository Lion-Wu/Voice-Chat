//
//  TTSSettingsSnapshot+SettingsManager.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

@MainActor
extension SettingsManager {
    var ttsSettingsSnapshot: TTSSettingsSnapshot {
        TTSSettingsSnapshot(
            serverAddress: serverSettings.serverAddress,
            textLanguage: serverSettings.textLang,
            autoSplit: modelSettings.autoSplit,
            enableStreaming: voiceSettings.enableStreaming,
            referenceAudioPath: selectedPreset?.refAudioPath ?? "",
            promptText: selectedPreset?.promptText ?? "",
            promptLanguage: selectedPreset?.promptLang ?? "auto",
            provider: voiceSettings.provider,
            appleSpeechVoiceIdentifier: voiceSettings.appleSpeechVoiceIdentifier,
            personalVoiceIdentifier: voiceSettings.personalVoiceIdentifier
        )
    }
}
