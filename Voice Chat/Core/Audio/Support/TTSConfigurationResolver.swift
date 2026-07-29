//
//  TTSConfigurationResolver.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct TTSConfigurationResolver: Sendable {
    let mediaType: String

    func constructTTSURL(from rawAddress: String) -> URL? {
        let raw = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let normalized: String
        if raw.contains("://") {
            normalized = raw
        } else {
            normalized = "http://\(raw)"
        }

        guard var comps = URLComponents(string: normalized) else { return nil }
        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }
        comps.path = path + "/tts"
        return comps.url
    }

    func makeConfiguration(
        snapshot: TTSSettingsSnapshot,
        isRealtime: Bool
    ) -> TTSSynthesisConfiguration? {
        if snapshot.provider.usesAppleSpeechSynthesizer {
            let voiceIdentifier: String?
            switch snapshot.provider {
            case .appleSpeech:
                voiceIdentifier = snapshot.appleSpeechVoiceIdentifier
            case .personalVoice:
                guard let selectedVoice = snapshot.personalVoiceIdentifier,
                      !selectedVoice.isEmpty else {
                    return nil
                }
                voiceIdentifier = selectedVoice
            case .gptSoVITS:
                voiceIdentifier = nil
            }
            return TTSSynthesisConfiguration(
                provider: snapshot.provider,
                appleSpeechVoiceIdentifier: voiceIdentifier,
                usesStreamingSegments: snapshot.enableStreaming
            )
        }

        let serverAddress = snapshot.serverAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = constructTTSURL(from: serverAddress) else { return nil }

        let splitMethod: String
        if isRealtime {
            splitMethod = "cut0"
        } else {
            splitMethod = snapshot.enableStreaming ? "cut0" : snapshot.autoSplit
        }

        return TTSSynthesisConfiguration(
            serverAddress: serverAddress,
            url: url,
            textLanguage: snapshot.textLanguage,
            referenceAudioPath: snapshot.referenceAudioPath,
            promptText: snapshot.promptText,
            promptLanguage: snapshot.promptLanguage,
            textSplitMethod: splitMethod,
            mediaType: mediaType,
            usesStreamingSegments: snapshot.enableStreaming
        )
    }
}
