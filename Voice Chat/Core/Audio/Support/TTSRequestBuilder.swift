//
//  TTSRequestBuilder.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

enum TTSRequestBuilderError: LocalizedError, Equatable {
    case serializationFailed
    case unsupportedProvider
    case missingEndpoint

    var errorDescription: String? {
        switch self {
        case .serializationFailed:
            return NSLocalizedString("Unable to serialize JSON", comment: "Shown when encoding the TTS request body fails")
        case .unsupportedProvider:
            return NSLocalizedString("The selected speech provider does not use an HTTP request.", comment: "Shown when an HTTP request is incorrectly requested for a local speech provider")
        case .missingEndpoint:
            return NSLocalizedString("The GPT-SoVITS endpoint is not configured.", comment: "Shown when the GPT-SoVITS endpoint is missing")
        }
    }
}

enum TTSRequestBuilder {
    static func makeRequest(
        for segmentText: String,
        configuration: TTSSynthesisConfiguration
    ) throws -> URLRequest {
        guard configuration.provider == .gptSoVITS else {
            throw TTSRequestBuilderError.unsupportedProvider
        }
        guard let url = configuration.url else {
            throw TTSRequestBuilderError.missingEndpoint
        }

        let params: [String: Any] = [
            "text": segmentText,
            "text_lang": configuration.textLanguage,
            "ref_audio_path": configuration.referenceAudioPath,
            "prompt_text": configuration.promptText,
            "prompt_lang": configuration.promptLanguage,
            "batch_size": 1,
            "media_type": configuration.mediaType,
            "text_split_method": configuration.textSplitMethod
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: params)
        } catch {
            throw TTSRequestBuilderError.serializationFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}
