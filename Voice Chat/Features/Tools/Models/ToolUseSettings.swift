//
//  ToolUseSettings.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

struct ToolUseSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var calendarEnabled: Bool
    var remindersEnabled: Bool
    var locationEnabled: Bool
    var motionEnabled: Bool
    var deviceContextEnabled: Bool
    var allowRemoteSensitiveTools: Bool

    init(
        isEnabled: Bool,
        calendarEnabled: Bool,
        remindersEnabled: Bool,
        locationEnabled: Bool,
        motionEnabled: Bool,
        deviceContextEnabled: Bool,
        allowRemoteSensitiveTools: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.calendarEnabled = calendarEnabled
        self.remindersEnabled = remindersEnabled
        self.locationEnabled = locationEnabled
        self.motionEnabled = motionEnabled
        self.deviceContextEnabled = deviceContextEnabled
        self.allowRemoteSensitiveTools = allowRemoteSensitiveTools
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        self.calendarEnabled = try container.decodeIfPresent(Bool.self, forKey: .calendarEnabled) ?? defaults.calendarEnabled
        self.remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? defaults.remindersEnabled
        self.locationEnabled = try container.decodeIfPresent(Bool.self, forKey: .locationEnabled) ?? defaults.locationEnabled
        self.motionEnabled = try container.decodeIfPresent(Bool.self, forKey: .motionEnabled) ?? defaults.motionEnabled
        self.deviceContextEnabled = try container.decodeIfPresent(Bool.self, forKey: .deviceContextEnabled) ?? defaults.deviceContextEnabled
        self.allowRemoteSensitiveTools = try container.decodeIfPresent(Bool.self, forKey: .allowRemoteSensitiveTools) ?? defaults.allowRemoteSensitiveTools
    }

    static let defaults = ToolUseSettings(
        isEnabled: false,
        calendarEnabled: false,
        remindersEnabled: false,
        locationEnabled: false,
        motionEnabled: false,
        deviceContextEnabled: false,
        allowRemoteSensitiveTools: false
    )

    var enabledToolIDs: Set<ChatToolID> {
        guard isEnabled else { return [] }
        var ids = Set<ChatToolID>()
        if calendarEnabled { ids.insert(.calendarListEvents) }
        if remindersEnabled { ids.insert(.remindersListReminders) }
        if locationEnabled { ids.insert(.locationCurrent) }
        if motionEnabled { ids.insert(.motionDevice) }
        if deviceContextEnabled { ids.insert(.deviceContext) }
        return ids
    }

    func enabledToolIDs(for endpoint: ChatAPIEndpointCandidate) -> Set<ChatToolID> {
        let ids = enabledToolIDs
        guard !allowsSensitiveTools(for: endpoint) else { return ids }
        return ids.subtracting(ChatToolID.sensitiveLocalDataToolIDs)
    }

    func allowsSensitiveTools(for endpoint: ChatAPIEndpointCandidate) -> Bool {
        allowRemoteSensitiveTools || ChatToolEndpointTrust.isTrustedLocalEndpoint(endpoint)
    }
}

extension ChatToolID {
    static let sensitiveLocalDataToolIDs: Set<ChatToolID> = [
        .calendarListEvents,
        .remindersListReminders,
        .locationCurrent,
        .motionDevice
    ]
}

enum ChatToolEndpointTrust {
    static func isTrustedLocalEndpoint(_ endpoint: ChatAPIEndpointCandidate) -> Bool {
        guard let host = endpoint.chatURL.host, !host.isEmpty else { return false }
        return ChatEndpointBaseURL.isLocalHost(host)
    }
}

enum ToolUseSettingsCodec {
    static func encode(_ settings: ToolUseSettings) -> String? {
        guard let data = try? JSONEncoder().encode(settings) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from raw: String?, fallback: ToolUseSettings = .defaults) -> ToolUseSettings {
        guard let raw,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ToolUseSettings.self, from: data) else {
            return fallback
        }
        return decoded
    }
}
