//
//  SettingsDefaults.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

enum SettingsDefaults {
    static let serverAddress = "http://localhost:9880"
    static let textLang = "auto"
    static let promptLang = "auto"
    static let modelLanguage = "auto"
    static let autoSplit = "cut0"
    static let apiURL = "http://localhost:1234"
    static let enableStreaming = true
    static let developerModeEnabled = false
    static let hapticFeedbackEnabled = true
    static let apiAdvancedSettings = APIAdvancedSettings.defaults
}
