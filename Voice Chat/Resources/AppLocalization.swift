//
//  AppLocalization.swift
//  Voice Chat
//
//  Created by ChatGPT on 2025/03/15.
//

import SwiftUI

/// Centralized access to localized strings used across the application.
enum AppLocalization {
    /// Keys mapped to entries in the localization files.
    enum Key: String {
        case speechPermissionDenied = "speech_permission_denied"
        case speechUnsupportedPlatform = "speech_unsupported_platform"
        case speechRecognizerUnavailable = "speech_recognizer_unavailable"
        case speechEngineStartFailed = "speech_engine_start_failed"
        case networkTimeout = "network_timeout"
    }

    /// Returns a `LocalizedStringKey` that can be used directly inside SwiftUI views.
    static func text(_ key: Key) -> LocalizedStringKey {
        LocalizedStringKey(key.rawValue)
    }

    /// Returns the localized string for imperative contexts (tooltips, accessibility, etc.).
    static func string(_ key: Key) -> String {
        NSLocalizedString(key.rawValue, comment: key.comment)
    }
}

private extension AppLocalization.Key {
    var comment: String {
        switch self {
        case .speechPermissionDenied:
            return "Error shown when the user denies speech or microphone permissions."
        case .speechUnsupportedPlatform:
            return "Error shown when speech input is not supported on the platform."
        case .speechRecognizerUnavailable:
            return "Error shown when the speech recognizer is unavailable."
        case .speechEngineStartFailed:
            return "Error shown when the audio engine fails to start."
        case .networkTimeout:
            return "Error shown when a streaming network request times out."
        }
    }
}
