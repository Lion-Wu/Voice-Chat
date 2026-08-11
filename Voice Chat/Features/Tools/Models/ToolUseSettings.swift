//
//  ToolUseSettings.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

enum ToolAuthorizationMode: String, Codable, CaseIterable, Sendable {
    case askEveryTime
    case readOnly
    case readWrite
}

struct ToolUseSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var calendarEnabled: Bool
    var remindersEnabled: Bool
    var locationEnabled: Bool
    var motionEnabled: Bool
    var deviceContextEnabled: Bool
    var clipboardEnabled: Bool
    var urlActionsEnabled: Bool
    var javaScriptRuntimeEnabled: Bool
    private var isTimeExplicitlyEnabled: Bool
    var timeEnabled: Bool {
        get { isTimeExplicitlyEnabled || requiresTimeTool }
        set { isTimeExplicitlyEnabled = newValue }
    }
    var authorizationMode: ToolAuthorizationMode
    var allowHighRiskToolAutoExecution: Bool
    var useProviderContinuationIDs: Bool
    var openAIResponsesStatefulEndpointURLs: [String]

    init(
        isEnabled: Bool,
        calendarEnabled: Bool,
        remindersEnabled: Bool,
        locationEnabled: Bool,
        motionEnabled: Bool,
        deviceContextEnabled: Bool,
        clipboardEnabled: Bool = false,
        urlActionsEnabled: Bool = false,
        javaScriptRuntimeEnabled: Bool = false,
        timeEnabled: Bool = false,
        authorizationMode: ToolAuthorizationMode = .readOnly,
        allowHighRiskToolAutoExecution: Bool = false,
        useProviderContinuationIDs: Bool = true,
        openAIResponsesStatefulEndpointURLs: [String] = ToolUseSettings.defaultOpenAIResponsesStatefulEndpointURLs
    ) {
        self.isEnabled = isEnabled
        self.calendarEnabled = calendarEnabled
        self.remindersEnabled = remindersEnabled
        self.locationEnabled = locationEnabled
        self.motionEnabled = motionEnabled
        self.deviceContextEnabled = deviceContextEnabled
        self.clipboardEnabled = clipboardEnabled
        self.urlActionsEnabled = urlActionsEnabled
        self.javaScriptRuntimeEnabled = javaScriptRuntimeEnabled
        self.isTimeExplicitlyEnabled = timeEnabled
        self.authorizationMode = authorizationMode
        self.allowHighRiskToolAutoExecution = allowHighRiskToolAutoExecution
        self.useProviderContinuationIDs = useProviderContinuationIDs
        self.openAIResponsesStatefulEndpointURLs = Self.normalizedOpenAIResponsesStatefulEndpointURLs(openAIResponsesStatefulEndpointURLs)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            calendarEnabled: try container.decode(Bool.self, forKey: .calendarEnabled),
            remindersEnabled: try container.decode(Bool.self, forKey: .remindersEnabled),
            locationEnabled: try container.decode(Bool.self, forKey: .locationEnabled),
            motionEnabled: try container.decode(Bool.self, forKey: .motionEnabled),
            deviceContextEnabled: try container.decode(Bool.self, forKey: .deviceContextEnabled),
            clipboardEnabled: try container.decode(Bool.self, forKey: .clipboardEnabled),
            urlActionsEnabled: try container.decode(Bool.self, forKey: .urlActionsEnabled),
            javaScriptRuntimeEnabled: try container.decodeIfPresent(Bool.self, forKey: .javaScriptRuntimeEnabled) ?? false,
            timeEnabled: try container.decode(Bool.self, forKey: .timeEnabled),
            authorizationMode: try container.decode(ToolAuthorizationMode.self, forKey: .authorizationMode),
            allowHighRiskToolAutoExecution: try container.decode(Bool.self, forKey: .allowHighRiskToolAutoExecution),
            useProviderContinuationIDs: try container.decode(Bool.self, forKey: .useProviderContinuationIDs),
            openAIResponsesStatefulEndpointURLs: try container.decode(
                [String].self,
                forKey: .openAIResponsesStatefulEndpointURLs
            )
        )
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case calendarEnabled
        case remindersEnabled
        case locationEnabled
        case motionEnabled
        case deviceContextEnabled
        case clipboardEnabled
        case urlActionsEnabled
        case javaScriptRuntimeEnabled
        case timeEnabled
        case authorizationMode
        case allowHighRiskToolAutoExecution
        case useProviderContinuationIDs
        case openAIResponsesStatefulEndpointURLs
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(calendarEnabled, forKey: .calendarEnabled)
        try container.encode(remindersEnabled, forKey: .remindersEnabled)
        try container.encode(locationEnabled, forKey: .locationEnabled)
        try container.encode(motionEnabled, forKey: .motionEnabled)
        try container.encode(deviceContextEnabled, forKey: .deviceContextEnabled)
        try container.encode(clipboardEnabled, forKey: .clipboardEnabled)
        try container.encode(urlActionsEnabled, forKey: .urlActionsEnabled)
        try container.encode(javaScriptRuntimeEnabled, forKey: .javaScriptRuntimeEnabled)
        try container.encode(isTimeExplicitlyEnabled, forKey: .timeEnabled)
        try container.encode(authorizationMode, forKey: .authorizationMode)
        try container.encode(allowHighRiskToolAutoExecution, forKey: .allowHighRiskToolAutoExecution)
        try container.encode(useProviderContinuationIDs, forKey: .useProviderContinuationIDs)
        try container.encode(
            Self.normalizedOpenAIResponsesStatefulEndpointURLs(openAIResponsesStatefulEndpointURLs),
            forKey: .openAIResponsesStatefulEndpointURLs
        )
    }

    static let defaultOpenAIResponsesStatefulEndpointURLs = [
        "https://api.openai.com/v1/responses"
    ]

    static let defaults = ToolUseSettings(
        isEnabled: false,
        calendarEnabled: false,
        remindersEnabled: false,
        locationEnabled: false,
        motionEnabled: false,
        deviceContextEnabled: false,
        clipboardEnabled: false,
        urlActionsEnabled: false,
        javaScriptRuntimeEnabled: false,
        timeEnabled: false,
        authorizationMode: .readOnly,
        allowHighRiskToolAutoExecution: false,
        useProviderContinuationIDs: true,
        openAIResponsesStatefulEndpointURLs: defaultOpenAIResponsesStatefulEndpointURLs
    )

    func resettingDeveloperRequestPolicyToDefaults() -> ToolUseSettings {
        var next = self
        let defaults = Self.defaults
        next.useProviderContinuationIDs = defaults.useProviderContinuationIDs
        next.openAIResponsesStatefulEndpointURLs = defaults.openAIResponsesStatefulEndpointURLs
        return next
    }

    var requiresTimeTool: Bool {
        selectedNonTimeToolIDs.contains { toolID in
            toolID.generalRuleRequirements.contains(.dateTime)
        }
    }

    var enabledToolIDs: Set<ChatToolID> {
        guard isEnabled else { return [] }
        var ids = selectedNonTimeToolIDs
        if timeEnabled { ids.insert(.systemGetTime) }
        return ids
    }

    private var selectedNonTimeToolIDs: Set<ChatToolID> {
        var ids = Set<ChatToolID>()
        if calendarEnabled {
            ids.insert(.calendarListEvents)
            ids.insert(.calendarCreateEvent)
            ids.insert(.calendarDeleteEvent)
            ids.insert(.calendarShowEvents)
        }
        if remindersEnabled {
            ids.insert(.remindersListReminders)
            ids.insert(.remindersCreateReminder)
            ids.insert(.remindersDeleteReminder)
            ids.insert(.remindersShowReminders)
        }
        if locationEnabled { ids.insert(.locationCurrent) }
        if motionEnabled { ids.insert(.motionDevice) }
        if deviceContextEnabled { ids.insert(.deviceContext) }
        if clipboardEnabled {
            ids.insert(.clipboardGetText)
            ids.insert(.clipboardSetText)
        }
        if urlActionsEnabled { ids.insert(.systemOpenURL) }
        if javaScriptRuntimeEnabled { ids.insert(.javaScriptRun) }
        return ids
    }

    func useProviderContinuationIDs(for endpoint: ChatAPIEndpointCandidate) -> Bool {
        switch endpoint.style {
        case .lmStudioRESTV1:
            return useProviderContinuationIDs
        case .openAIResponses:
            break
        case .openAIChatCompletions, .anthropicMessages:
            return false
        }
        guard let key = Self.providerContinuationIDPreferenceKey(for: endpoint) else {
            return false
        }
        return Self.normalizedOpenAIResponsesStatefulEndpointURLs(openAIResponsesStatefulEndpointURLs).contains(key)
    }

    mutating func enableOpenAIResponsesStatefulChat(for endpoint: ChatAPIEndpointCandidate) {
        guard let key = Self.providerContinuationIDPreferenceKey(for: endpoint) else { return }
        var urls = Self.normalizedOpenAIResponsesStatefulEndpointURLs(openAIResponsesStatefulEndpointURLs)
        guard !urls.contains(key) else { return }
        urls.append(key)
        openAIResponsesStatefulEndpointURLs = urls
    }

    mutating func removeOpenAIResponsesStatefulEndpointURL(_ endpointURL: String) {
        let normalized = Self.normalizedEndpointURL(endpointURL)
        openAIResponsesStatefulEndpointURLs = Self.normalizedOpenAIResponsesStatefulEndpointURLs(openAIResponsesStatefulEndpointURLs)
            .filter { $0 != normalized }
    }

    func isOpenAIResponsesStatefulChatEnabled(for endpoint: ChatAPIEndpointCandidate) -> Bool {
        guard let key = Self.providerContinuationIDPreferenceKey(for: endpoint) else { return false }
        return Self.normalizedOpenAIResponsesStatefulEndpointURLs(openAIResponsesStatefulEndpointURLs).contains(key)
    }

    static func providerContinuationIDPreferenceKey(for endpoint: ChatAPIEndpointCandidate) -> String? {
        guard supportsProviderContinuationIDPreference(for: endpoint) else { return nil }
        return normalizedEndpointURL(endpoint.chatURL)
    }

    static func supportsProviderContinuationIDPreference(for endpoint: ChatAPIEndpointCandidate) -> Bool {
        endpoint.provider == .openAI && endpoint.style == .openAIResponses
    }

    static func normalizedOpenAIResponsesStatefulEndpointURLs(_ urls: [String]) -> [String] {
        normalizedEndpointURLList(urls)
    }

    private static func normalizedEndpointURLList(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for url in urls {
            let key = normalizedEndpointURL(url)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            normalized.append(key)
        }
        return normalized
    }

    private static func normalizedEndpointURL(_ rawURL: String) -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            return trimmed.lowercased()
        }
        return normalizedEndpointURL(url)
    }

    private static func normalizedEndpointURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.query = nil
        components.fragment = nil
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        components.path = path.isEmpty ? "" : "/" + path
        return components.url?.absoluteString ?? url.absoluteString.lowercased()
    }
}

enum ChatToolAuthorizationPolicy {
    enum Decision: Equatable {
        case allow
        case ask
        case deny(String)
    }

    static func decision(
        for toolID: ChatToolID,
        settings: ToolUseSettings,
        endpoint _: ChatAPIEndpointCandidate
    ) -> Decision {
        if toolID.requiresHighRiskAutoExecution && !settings.allowHighRiskToolAutoExecution {
            return .ask
        }

        switch settings.authorizationMode {
        case .askEveryTime:
            return .ask
        case .readOnly:
            switch toolID.operationKind {
            case .read, .display:
                return .allow
            case .write, .action, .compute:
                return .ask
            }
        case .readWrite:
            switch toolID.operationKind {
            case .read, .write, .display, .action, .compute:
                return .allow
            }
        }
    }
}

private extension ChatToolID {
    var requiresHighRiskAutoExecution: Bool {
        switch self {
        case .locationCurrent, .clipboardGetText, .clipboardSetText, .systemOpenURL, .javaScriptRun:
            return true
        default:
            return false
        }
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
