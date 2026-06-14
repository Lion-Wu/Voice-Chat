//
//  APIAdvancedSettingsCodec.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

enum APIAdvancedSettingsCodec {
    static func decode(
        from json: String?,
        fallback: APIAdvancedSettings = .defaults
    ) -> APIAdvancedSettings {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else {
            return fallback.sanitized
        }
        guard let decoded = try? JSONDecoder().decode(APIAdvancedSettings.self, from: data) else {
            return fallback.sanitized
        }
        return decoded.sanitized
    }

    static func encode(_ settings: APIAdvancedSettings) -> String? {
        guard let data = try? JSONEncoder().encode(settings.sanitized) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
