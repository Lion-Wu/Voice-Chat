//
//  TTSSettingsSnapshot.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

enum TTSProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case gptSoVITS
    case appleSpeech
    case personalVoice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gptSoVITS:
            return "GPT-SoVITS"
        case .appleSpeech:
            return NSLocalizedString("Apple Speech", comment: "Apple's built-in text-to-speech provider")
        case .personalVoice:
            return NSLocalizedString("Apple Personal Voice", comment: "Apple accessibility Personal Voice provider")
        }
    }

    var requiresNetworkTTSService: Bool {
        self == .gptSoVITS
    }

    var usesAppleSpeechSynthesizer: Bool {
        self == .appleSpeech || self == .personalVoice
    }
}

struct TTSSettingsSnapshot: Equatable, Sendable {
    var serverAddress: String
    var textLanguage: String
    var autoSplit: String
    var enableStreaming: Bool
    var referenceAudioPath: String
    var promptText: String
    var promptLanguage: String
    var provider: TTSProvider
    var appleSpeechVoiceIdentifier: String?
    var personalVoiceIdentifier: String?

    init(
        serverAddress: String,
        textLanguage: String,
        autoSplit: String,
        enableStreaming: Bool,
        referenceAudioPath: String,
        promptText: String,
        promptLanguage: String,
        provider: TTSProvider = .gptSoVITS,
        appleSpeechVoiceIdentifier: String? = nil,
        personalVoiceIdentifier: String? = nil
    ) {
        self.serverAddress = serverAddress
        self.textLanguage = textLanguage
        self.autoSplit = autoSplit
        self.enableStreaming = enableStreaming
        self.referenceAudioPath = referenceAudioPath
        self.promptText = promptText
        self.promptLanguage = promptLanguage
        self.provider = provider
        self.appleSpeechVoiceIdentifier = appleSpeechVoiceIdentifier
        self.personalVoiceIdentifier = personalVoiceIdentifier
    }

    static let defaults = TTSSettingsSnapshot(
        serverAddress: "http://localhost:9880",
        textLanguage: "auto",
        autoSplit: "cut0",
        enableStreaming: true,
        referenceAudioPath: "",
        promptText: "",
        promptLanguage: "auto",
        provider: .gptSoVITS,
        appleSpeechVoiceIdentifier: nil,
        personalVoiceIdentifier: nil
    )
}
