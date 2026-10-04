//
//  ChatModelCapabilityStore.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatModelCapabilityStore: Equatable {
    private(set) var imageInputSupport: [String: Bool]
    private(set) var imageInputOverrides: [String: Bool]
    private(set) var thinkingCapabilities: [String: ModelThinkingCapability]
    private(set) var thinkingPreferences: [String: ModelThinkingOption]
    private(set) var detectedProviderHints: [String: ChatProvider]
    private(set) var detectedRequestStyleHints: [String: ChatRequestStyle]

    static func restoringPreferences(from settings: AppSettings) -> Self {
        let rawThinking: [String: String] = decodeDictionary(settings.modelThinkingPreferencesJSON)
        var store = Self(
            imageInputOverrides: decodeImageInputOverrides(from: settings.modelImageInputOverrideJSON),
            thinkingPreferences: rawThinking.compactMapValues(ModelThinkingOption.normalized)
        )
        let records: [String: [String: String]] = decodeDictionary(settings.detectedAPIFormatsJSON)
        for (base, record) in records {
            guard let providerRaw = record["provider"], let provider = ChatProvider(rawValue: providerRaw),
                  let styleRaw = record["style"], let style = ChatRequestStyle(rawValue: styleRaw) else { continue }
            store.detectedProviderHints[base] = provider
            store.detectedRequestStyleHints[base] = style
        }
        return store
    }

    func savePreferences(to settings: AppSettings) throws {
        var records: [String: [String: String]] = [:]
        for (base, style) in detectedRequestStyleHints {
            guard let provider = detectedProviderHints[base] else { continue }
            records[base] = ["provider": provider.rawValue, "style": style.rawValue]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let formats = try encoder.encode(records)
        let thinking = try encoder.encode(thinkingPreferences.mapValues(\.rawValue))
        let overrides = imageInputOverrides.isEmpty ? nil : String(decoding: try encoder.encode(imageInputOverrides), as: UTF8.self)
        settings.detectedAPIFormatsJSON = String(decoding: formats, as: UTF8.self)
        settings.modelThinkingPreferencesJSON = String(decoding: thinking, as: UTF8.self)
        settings.modelImageInputOverrideJSON = overrides
    }

    init(
        imageInputSupport: [String: Bool] = [:],
        imageInputOverrides: [String: Bool] = [:],
        thinkingCapabilities: [String: ModelThinkingCapability] = [:],
        thinkingPreferences: [String: ModelThinkingOption] = [:],
        detectedProviderHints: [String: ChatProvider] = [:],
        detectedRequestStyleHints: [String: ChatRequestStyle] = [:]
    ) {
        self.imageInputSupport = imageInputSupport
        self.imageInputOverrides = imageInputOverrides
        self.thinkingCapabilities = thinkingCapabilities
        self.thinkingPreferences = thinkingPreferences
        self.detectedProviderHints = detectedProviderHints
        self.detectedRequestStyleHints = detectedRequestStyleHints
    }

    static func scopedKey(apiBaseURL: String, modelIdentifier: String) -> String? {
        let trimmedModel = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { return nil }
        guard let endpointKey = ChatAPIEndpointResolver.normalizedAPIBaseKey(apiBaseURL) else { return nil }
        return "\(endpointKey)|\(trimmedModel)"
    }

    private static func decodeDictionary<Value: Decodable>(_ json: String?) -> [String: Value] {
        guard let json, let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Value].self, from: data)) ?? [:]
    }

    static func decodeImageInputOverrides(from json: String?) -> [String: Bool] {
        decodeDictionary(json)
    }

    mutating func updateImageInputSupport(_ supportByModel: [String: Bool], for apiBaseURL: String) {
        guard let prefix = Self.scopedPrefix(for: apiBaseURL) else { return }

        imageInputSupport.keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { imageInputSupport.removeValue(forKey: $0) }

        for (modelID, supportsImageInput) in supportByModel {
            guard let key = Self.scopedKey(apiBaseURL: apiBaseURL, modelIdentifier: modelID) else { continue }
            imageInputSupport[key] = supportsImageInput
        }
    }

    mutating func updateThinkingCapabilities(
        _ capabilitiesByModel: [String: ModelThinkingCapability],
        for apiBaseURL: String
    ) {
        guard let prefix = Self.scopedPrefix(for: apiBaseURL) else { return }

        thinkingCapabilities.keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { thinkingCapabilities.removeValue(forKey: $0) }

        for (modelID, capability) in capabilitiesByModel {
            guard let key = Self.scopedKey(apiBaseURL: apiBaseURL, modelIdentifier: modelID) else { continue }
            thinkingCapabilities[key] = capability
        }
    }

    mutating func noteDetectedProvider(_ provider: ChatProvider, for apiBaseURL: String) {
        guard provider != .unknown else { return }
        guard let key = ChatAPIEndpointResolver.normalizedAPIBaseKey(apiBaseURL) else { return }
        detectedProviderHints[key] = provider
    }

    mutating func noteDetectedRequestStyle(_ style: ChatRequestStyle, for apiBaseURL: String) {
        guard let key = ChatAPIEndpointResolver.normalizedAPIBaseKey(apiBaseURL) else { return }
        detectedRequestStyleHints[key] = style
    }

    func detectedProvider(for apiBaseURL: String) -> ChatProvider? {
        guard let key = ChatAPIEndpointResolver.normalizedAPIBaseKey(apiBaseURL) else { return nil }
        return detectedProviderHints[key]
    }

    func detectedRequestStyle(for apiBaseURL: String) -> ChatRequestStyle? {
        guard let key = ChatAPIEndpointResolver.normalizedAPIBaseKey(apiBaseURL) else { return nil }
        return detectedRequestStyleHints[key]
    }

    func imageInputManualOverride(for modelIdentifier: String) -> Bool? {
        let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return imageInputOverrides[trimmed]
    }

    mutating func setImageInputManualOverride(_ enabled: Bool?, for modelIdentifier: String) {
        let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let enabled {
            imageInputOverrides[trimmed] = enabled
        } else {
            imageInputOverrides.removeValue(forKey: trimmed)
        }
    }

    func isImageInputSupportUnknown(for modelIdentifier: String, apiBaseURL: String) -> Bool {
        let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if explicitImageInputSupport(for: trimmed, apiBaseURL: apiBaseURL) != nil {
            return false
        }
        return ModelCapabilityResolver.imageInputSupport(fromModelIdentifier: trimmed) == nil
    }

    func supportsImageInput(for modelIdentifier: String, apiBaseURL: String) -> Bool {
        let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Provider-reported model capabilities should override stale manual toggles.
        if let explicit = explicitImageInputSupport(for: trimmed, apiBaseURL: apiBaseURL) {
            return explicit
        }
        if let manualOverride = imageInputOverrides[trimmed] {
            return manualOverride
        }
        if let inferred = ModelCapabilityResolver.imageInputSupport(fromModelIdentifier: trimmed) {
            return inferred
        }
        return false
    }

    func thinkingCapability(
        for modelIdentifier: String,
        apiBaseURL: String,
        provider: ChatProvider,
        requestStyle: ChatRequestStyle?
    ) -> ModelThinkingCapability? {
        let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let key = Self.scopedKey(apiBaseURL: apiBaseURL, modelIdentifier: trimmed),
           let explicit = thinkingCapabilities[key] {
            return explicit
        }

        return ModelCapabilityResolver.thinkingCapability(
            fromModelIdentifier: trimmed,
            provider: provider,
            requestStyle: requestStyle
        )
    }

    func selectedThinkingOption(
        for modelIdentifier: String,
        apiBaseURL: String,
        capability: ModelThinkingCapability
    ) -> ModelThinkingOption? {
        guard let key = Self.scopedKey(apiBaseURL: apiBaseURL, modelIdentifier: modelIdentifier) else {
            return nil
        }
        return capability.normalizedSelection(thinkingPreferences[key])
    }

    mutating func setSelectedThinkingOption(
        _ option: ModelThinkingOption?,
        for modelIdentifier: String,
        apiBaseURL: String,
        capability: ModelThinkingCapability
    ) {
        guard let key = Self.scopedKey(apiBaseURL: apiBaseURL, modelIdentifier: modelIdentifier) else {
            return
        }
        guard let normalized = capability.normalizedSelection(option) else { return }
        thinkingPreferences[key] = normalized
    }

    private func explicitImageInputSupport(for modelIdentifier: String, apiBaseURL: String) -> Bool? {
        guard let key = Self.scopedKey(apiBaseURL: apiBaseURL, modelIdentifier: modelIdentifier) else { return nil }
        return imageInputSupport[key]
    }

    private static func scopedPrefix(for apiBaseURL: String) -> String? {
        guard let endpointKey = ChatAPIEndpointResolver.normalizedAPIBaseKey(apiBaseURL) else { return nil }
        return "\(endpointKey)|"
    }
}
