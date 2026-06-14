//
//  SettingsChatModelCapabilityController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct SettingsChatModelCapabilityContext {
    let chatSettings: ChatSettings
    let chatServerPresets: [ChatServerPreset]
    let selectedChatServerPresetID: UUID?
}

@MainActor
final class SettingsChatModelCapabilityController {
    private let getStore: () -> ChatModelCapabilityStore
    private let setStore: (ChatModelCapabilityStore) -> Void
    private let context: () -> SettingsChatModelCapabilityContext
    private let saveImageInputOverrides: () -> Void

    init(
        getStore: @escaping () -> ChatModelCapabilityStore,
        setStore: @escaping (ChatModelCapabilityStore) -> Void,
        context: @escaping () -> SettingsChatModelCapabilityContext,
        saveImageInputOverrides: @escaping () -> Void
    ) {
        self.getStore = getStore
        self.setStore = setStore
        self.context = context
        self.saveImageInputOverrides = saveImageInputOverrides
    }

    func updateImageInputSupport(_ supportByModel: [String: Bool], for apiBaseURL: String) {
        updateStore {
            $0.updateImageInputSupport(supportByModel, for: apiBaseURL)
        }
    }

    func updateThinkingCapabilities(
        _ capabilitiesByModel: [String: ModelThinkingCapability],
        for apiBaseURL: String
    ) {
        updateStore {
            $0.updateThinkingCapabilities(capabilitiesByModel, for: apiBaseURL)
        }
    }

    func noteDetectedProvider(_ provider: ChatProvider, for apiBaseURL: String) {
        updateStore {
            $0.noteDetectedProvider(provider, for: apiBaseURL)
        }
    }

    func noteDetectedRequestStyle(_ style: ChatRequestStyle, for apiBaseURL: String) {
        updateStore {
            $0.noteDetectedRequestStyle(style, for: apiBaseURL)
        }
    }

    func noteDetectedEndpoint(_ endpoint: ChatAPIEndpointCandidate, for apiBaseURL: String) {
        updateStore {
            $0.noteDetectedEndpoint(endpoint, for: apiBaseURL)
        }
    }

    func detectedProvider(for apiBaseURL: String) -> ChatProvider? {
        facade.detectedProvider(for: apiBaseURL)
    }

    func detectedRequestStyle(for apiBaseURL: String) -> ChatRequestStyle? {
        facade.detectedRequestStyle(for: apiBaseURL)
    }

    func chatAPIFormatPreference(for presetID: UUID?) -> ChatAPIFormatPreference {
        facade.chatAPIFormatPreference(for: presetID)
    }

    func selectedChatAPIFormatPreference() -> ChatAPIFormatPreference {
        facade.selectedChatAPIFormatPreference()
    }

    func resolvedProvider(for apiBaseURL: String) -> ChatProvider? {
        facade.resolvedProvider(for: apiBaseURL)
    }

    func resolvedRequestStyle(for apiBaseURL: String) -> ChatRequestStyle? {
        facade.resolvedRequestStyle(for: apiBaseURL)
    }

    func imageInputManualOverride(for modelIdentifier: String) -> Bool? {
        facade.imageInputManualOverride(for: modelIdentifier)
    }

    func setImageInputManualOverride(_ enabled: Bool?, for modelIdentifier: String) {
        updateStore {
            $0.setImageInputManualOverride(enabled, for: modelIdentifier)
        }
        saveImageInputOverrides()
    }

    func isImageInputSupportUnknown(for modelIdentifier: String) -> Bool {
        facade.isImageInputSupportUnknown(for: modelIdentifier)
    }

    func supportsImageInput(for modelIdentifier: String) -> Bool {
        facade.supportsImageInput(for: modelIdentifier)
    }

    func thinkingCapability(for modelIdentifier: String) -> ModelThinkingCapability? {
        facade.thinkingCapability(for: modelIdentifier)
    }

    func selectedThinkingOption(for modelIdentifier: String? = nil) -> ModelThinkingOption? {
        facade.selectedThinkingOption(for: modelIdentifier)
    }

    func setSelectedThinkingOption(_ option: ModelThinkingOption?, for modelIdentifier: String? = nil) {
        var nextFacade = facade
        guard nextFacade.setSelectedThinkingOption(option, for: modelIdentifier) else { return }
        setStore(nextFacade.store)
        nextFacade.store.saveThinkingPreferences()
    }

    func toggleSelectedThinking(for modelIdentifier: String? = nil) {
        var nextFacade = facade
        guard nextFacade.toggleSelectedThinking(for: modelIdentifier) else { return }
        setStore(nextFacade.store)
        nextFacade.store.saveThinkingPreferences()
    }

    private var facade: ChatModelCapabilityFacade {
        let snapshot = context()
        return ChatModelCapabilityFacade(
            store: getStore(),
            chatSettings: snapshot.chatSettings,
            chatServerPresets: snapshot.chatServerPresets,
            selectedChatServerPresetID: snapshot.selectedChatServerPresetID
        )
    }

    private func updateStore(_ mutate: (inout ChatModelCapabilityFacade) -> Void) {
        var nextFacade = facade
        mutate(&nextFacade)
        setStore(nextFacade.store)
    }
}
