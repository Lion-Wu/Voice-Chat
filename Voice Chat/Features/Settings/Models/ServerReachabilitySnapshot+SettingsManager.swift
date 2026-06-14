//
//  ServerReachabilitySnapshot+SettingsManager.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

@MainActor
extension SettingsManager {
    var serverReachabilitySnapshot: ServerReachabilitySnapshot {
        ServerReachabilitySnapshot(
            chatBaseURL: chatSettings.apiURL,
            ttsBaseURL: serverSettings.serverAddress
        )
    }
}
