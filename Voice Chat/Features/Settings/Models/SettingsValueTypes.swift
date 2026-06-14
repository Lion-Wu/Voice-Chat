//
//  SettingsValueTypes.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation

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
