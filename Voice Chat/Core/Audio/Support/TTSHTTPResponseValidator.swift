//
//  TTSHTTPResponseValidator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct TTSHTTPResponseFailure: Equatable {
    let disposition: TTSFailureDisposition
    let message: String
}

enum TTSHTTPResponseValidator {
    static func failure(for response: URLResponse?, data: Data?) -> TTSHTTPResponseFailure? {
        guard let http = response as? HTTPURLResponse else { return nil }

        if !(200...299).contains(http.statusCode) {
            return TTSHTTPResponseFailure(
                disposition: disposition(forHTTPStatusCode: http.statusCode),
                message: serverErrorMessage(statusCode: http.statusCode, data: data)
            )
        }

        if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           !type.contains("audio") && !type.contains("octet-stream") {
            return TTSHTTPResponseFailure(
                disposition: .content,
                message: nonAudioMessage(data: data)
            )
        }

        return nil
    }

    private static func disposition(forHTTPStatusCode statusCode: Int) -> TTSFailureDisposition {
        if NetworkRetryability.shouldRetry(statusCode: statusCode) {
            return .transient
        }
        switch statusCode {
        case 400, 413, 422:
            return .content
        default:
            return .fatal
        }
    }

    private static func serverErrorMessage(statusCode: Int, data: Data?) -> String {
        let preview = bodyPreview(from: data)
        if preview.isEmpty {
            return String(
                format: NSLocalizedString("TTS server error: %d", comment: "Shown when the TTS server returns a non-success status"),
                statusCode
            )
        }

        return String(
            format: NSLocalizedString("TTS server error: %d (%@)", comment: "Shown when the TTS server returns a non-success status plus body"),
            statusCode,
            preview
        )
    }

    private static func nonAudioMessage(data: Data?) -> String {
        let preview = bodyPreview(from: data)
        if preview.isEmpty {
            return NSLocalizedString("TTS response was not audio data.", comment: "Shown when TTS returns a non-audio MIME type")
        }

        return String(
            format: NSLocalizedString("TTS response was not audio: %@", comment: "Shown when TTS returns non-audio body"),
            preview
        )
    }

    private static func bodyPreview(from data: Data?) -> String {
        let preview = data.flatMap { String(data: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(preview.prefix(180))
    }
}
