//
//  SettingsManager+LaunchTasks.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension SettingsManager {
    func applyPresetOnLaunchIfNeeded() async {
        await presetApplyController.applyOnLaunchIfNeeded {
            selectedPresetApplyRequest()
        }
    }

    func prefetchChatModelsOnLaunchIfNeeded() async {
        guard !didPrefetchChatModelsOnLaunch else { return }
        didPrefetchChatModelsOnLaunch = true
        await refreshChatProviderHintsAndModels()
    }

    func refreshChatProviderHintsAndModels() async {
        let rawBase = chatSettings.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawBase.isEmpty else { return }

        guard let result = await chatModelCatalogRefreshCoordinator.refresh(
            chatSettings: chatSettings,
            formatPreference: chatModelCapabilities.selectedChatAPIFormatPreference(),
            detectedProvider: chatModelCapabilities.detectedProvider(for: rawBase)
        ) else { return }

        let currentRawBase = chatSettings.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ChatAPIEndpointResolver.normalizedAPIBaseKey(currentRawBase) == ChatAPIEndpointResolver.normalizedAPIBaseKey(result.rawBase) else {
            return
        }

        chatModelCapabilities.noteDetectedEndpoint(result.endpoint, for: result.rawBase)
        chatModelCapabilities.updateImageInputSupport(result.imageInputSupportByModelID, for: result.rawBase)
        chatModelCapabilities.updateThinkingCapabilities(result.thinkingCapabilitiesByModelID, for: result.rawBase)

        let selected = chatSettings.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let availableModelIDs = Set(result.modelIDs)
        if !result.models.isEmpty && (selected.isEmpty || !availableModelIDs.contains(selected)),
           let firstModel = result.models.first?.id {
            updateChatSettings(apiURL: chatSettings.apiURL, selectedModel: firstModel)
        }
    }

    func applySelectedPreset() async {
        await presetApplyController.apply(selectedPresetApplyRequest())
    }
}
