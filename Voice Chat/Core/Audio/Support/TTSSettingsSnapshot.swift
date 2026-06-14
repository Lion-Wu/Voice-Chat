//
//  TTSSettingsSnapshot.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct TTSSettingsSnapshot: Equatable, Sendable {
    var serverAddress: String
    var textLanguage: String
    var autoSplit: String
    var enableStreaming: Bool
    var referenceAudioPath: String
    var promptText: String
    var promptLanguage: String

    static let defaults = TTSSettingsSnapshot(
        serverAddress: "http://localhost:9880",
        textLanguage: "auto",
        autoSplit: "cut0",
        enableStreaming: true,
        referenceAudioPath: "",
        promptText: "",
        promptLanguage: "auto"
    )
}
