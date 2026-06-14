//
//  SettingsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.10.09.
//

import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []
    let suppression = SettingsViewModelSuppressionController()
    private var didSyncAfterStoreLoad = false

    // MARK: - Settings
    @Published var serverAddress: String { didSet { if !suppression.isActive(.autoSaves) { saveServerSettings() } } }
    @Published var textLang: String { didSet { if !suppression.isActive(.autoSaves) { saveServerSettings() } } }

    @Published var apiURL: String { didSet { if !suppression.isActive(.autoSaves) { saveChatSettings() } } }
    @Published var selectedModel: String { didSet { if !suppression.isActive(.autoSaves) { saveChatSettings() } } }
    @Published var chatAPIKey: String { didSet { if !suppression.isActive(.autoSaves) { saveChatAPIKey() } } }

    @Published var enableStreaming: Bool {
        didSet {
            guard !suppression.isActive(.autoSaves) else { return }
            saveVoiceSettings()
            if enableStreaming {
                // Force `cut0` when streaming is enabled.
                autoSplit = "cut0"
            }
        }
    }

    @Published var autoSplit: String {
        didSet {
            guard !suppression.isActive(.autoSaves) else { return }
            saveModelSettings()
        }
    }
    @Published var modelId: String { didSet { if !suppression.isActive(.autoSaves) { saveModelSettings() } } }
    @Published var language: String { didSet { if !suppression.isActive(.autoSaves) { saveModelSettings() } } }
    @Published var hapticFeedbackEnabled: Bool {
        didSet {
            guard !suppression.isActive(.autoSaves) else { return }
            saveHapticFeedbackSettings()
        }
    }
    @Published var apiAdvancedSettings: APIAdvancedSettings {
        didSet {
            guard !suppression.isActive(.autoSaves) else { return }
            saveAPIAdvancedSettings()
        }
    }

    // MARK: - Model List (Networking)

    @Published private(set) var availableModels: [String] = []
    @Published private(set) var isLoadingModels: Bool = false
    @Published private(set) var isRetryingModels: Bool = false
    @Published private(set) var modelRetryAttempt: Int = 0
    @Published private(set) var modelRetryLastError: String?
    @Published private(set) var chatServerErrorMessage: String?
    @Published private(set) var lastFetchedModelMetadata: [ModelInfo] = []
    @Published private(set) var lastModelFetchEndpoint: ChatAPIEndpointCandidate?

    // MARK: - Preset bindings for the UI
    typealias PresetSummary = SettingsPresetSummary

    // MARK: - Voice server presets
    @Published var voiceServerPresetList: [PresetSummary] = []
    @Published var selectedVoiceServerPresetID: UUID? {
        didSet {
            if !suppression.isActive(.voiceServerPresetDidSet) {
                presetBindingController.selectVoiceServerPreset(selectedVoiceServerPresetID)
                refreshFromSettingsManager()
            }
        }
    }
    @Published var voiceServerPresetName: String = "" { didSet { saveSelectedVoiceServerPresetName() } }

    // MARK: - Chat server presets
    @Published var chatServerPresetList: [PresetSummary] = []
    @Published var selectedChatServerPresetID: UUID? {
        didSet {
            if !suppression.isActive(.chatServerPresetDidSet) {
                presetBindingController.selectChatServerPreset(selectedChatServerPresetID)
                refreshFromSettingsManager()
            }
        }
    }
    @Published var chatServerPresetName: String = "" { didSet { saveSelectedChatServerPresetName() } }
    @Published var selectedChatAPIFormatPreference: ChatAPIFormatPreference = .automatic {
        didSet { saveSelectedChatServerPresetAPIFormatPreference() }
    }

    @Published var presetList: [PresetSummary] = []
    @Published var selectedPresetID: UUID? {
        didSet {
            if !suppression.isActive(.voicePresetDidSet) {
                presetBindingController.selectVoicePreset(selectedPresetID, apply: true)
                // Reload the preset fields after switching selection.
                loadSelectedPresetFields()
            }
        }
    }

    @Published var presetName: String = ""          { didSet { savePresetFields() } }
    @Published var presetRefAudioPath: String = ""  { didSet { savePresetFields() } }
    @Published var presetPromptText: String = ""    { didSet { savePresetFields() } }
    @Published var presetPromptLang: String = "auto" { didSet { savePresetFields() } }
    @Published var presetGPTWeightsPath: String = "" { didSet { savePresetFields() } }
    @Published var presetSoVITSWeightsPath: String = "" { didSet { savePresetFields() } }

    // MARK: - System prompt presets (normal / voice are separate)

    @Published var normalSystemPromptPresetList: [PresetSummary] = []
    @Published var selectedNormalSystemPromptPresetID: UUID? {
        didSet {
            if !suppression.isActive(.normalSystemPromptDidSet) {
                presetBindingController.selectNormalSystemPromptPreset(selectedNormalSystemPromptPresetID)
                loadSelectedNormalSystemPromptPresetFields()
            }
        }
    }
    @Published var normalSystemPromptPresetName: String = "" { didSet { saveSelectedNormalSystemPromptPresetName() } }
    @Published var normalSystemPromptPrompt: String = "" { didSet { saveSelectedNormalSystemPromptPresetPrompt() } }

    @Published var voiceSystemPromptPresetList: [PresetSummary] = []
    @Published var selectedVoiceSystemPromptPresetID: UUID? {
        didSet {
            if !suppression.isActive(.voiceSystemPromptDidSet) {
                presetBindingController.selectVoiceSystemPromptPreset(selectedVoiceSystemPromptPresetID)
                loadSelectedVoiceSystemPromptPresetFields()
            }
        }
    }
    @Published var voiceSystemPromptPresetName: String = "" { didSet { saveSelectedVoiceSystemPromptPresetName() } }
    @Published var voiceSystemPromptPrompt: String = "" { didSet { saveSelectedVoiceSystemPromptPresetPrompt() } }

    // MARK: - Dependency
    let settingsManager: SettingsManager
    let presetBindingController: SettingsPresetBindingController
    private let modelCatalogController: SettingsModelCatalogController

    func withSuppressed(
        _ flag: SettingsViewModelSuppressionController.Flag,
        perform body: () -> Void
    ) {
        suppression.withSuppressed(flag, perform: body)
    }

    func withSuppressed(
        _ flags: [SettingsViewModelSuppressionController.Flag],
        perform body: () -> Void
    ) {
        suppression.withSuppressed(flags, perform: body)
    }

    // MARK: - Init
    init(
        settingsManager: SettingsManager = .shared,
        modelCatalogService: ModelCatalogFetching = DefaultModelCatalogService()
    ) {
        self.settingsManager = settingsManager
        self.presetBindingController = SettingsPresetBindingController(settingsManager: settingsManager)
        self.modelCatalogController = SettingsModelCatalogController(
            modelCatalogFetchCoordinator: ModelCatalogFetchCoordinator(modelCatalogService: modelCatalogService)
        )
        // Seed values from the current in-memory state. A later SwiftData attach may update the manager,
        // so we also listen for the first post-load signal and resync.
        serverAddress = ""
        textLang = ""

        apiURL = ""
        selectedModel = ""
        chatAPIKey = ""
        selectedChatAPIFormatPreference = .automatic

        selectedVoiceServerPresetID = nil

        enableStreaming = true

        autoSplit = "cut0"
        modelId = ""
        language = "auto"
        hapticFeedbackEnabled = true
        apiAdvancedSettings = .defaults

        refreshFromSettingsManager()
        bindInitialStoreSync()
    }

    var shouldShowUnknownModelImageInputToggle: Bool {
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return false }
        return settingsManager.chatModelCapabilities.isImageInputSupportUnknown(for: model)
    }

    var isSelectedUnknownModelImageInputEnabled: Bool {
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return false }
        return settingsManager.chatModelCapabilities.imageInputManualOverride(for: model) == true
    }

    func setSelectedUnknownModelImageInputEnabled(_ enabled: Bool) {
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        // Persist explicit per-model choice for unknown-capability models.
        settingsManager.chatModelCapabilities.setImageInputManualOverride(enabled, for: model)
        objectWillChange.send()
    }

    // MARK: - Networking (List Models)

    func fetchAvailableModels() {
        let trimmedAPIURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        modelCatalogController.fetch(
            request: SettingsModelCatalogRequest(
                apiURL: trimmedAPIURL,
                apiKey: chatAPIKey,
                formatPreference: settingsManager.chatModelCapabilities.chatAPIFormatPreference(for: settingsManager.selectedChatServerPresetID),
                detectedProvider: settingsManager.chatModelCapabilities.detectedProvider(for: trimmedAPIURL),
                selectedModel: selectedModel
            ),
            currentState: currentModelCatalogState(),
            applyState: { [weak self] state in
                self?.applyModelCatalogState(state)
            },
            applyDetection: { [weak self] detection in
                self?.applyDetectedModels(detection)
            }
        )
    }

    private func currentModelCatalogState() -> SettingsModelCatalogState {
        SettingsModelCatalogState(
            availableModels: availableModels,
            isLoadingModels: isLoadingModels,
            isRetryingModels: isRetryingModels,
            modelRetryAttempt: modelRetryAttempt,
            modelRetryLastError: modelRetryLastError,
            chatServerErrorMessage: chatServerErrorMessage,
            lastFetchedModelMetadata: lastFetchedModelMetadata,
            lastModelFetchEndpoint: lastModelFetchEndpoint
        )
    }

    private func applyModelCatalogState(_ state: SettingsModelCatalogState) {
        availableModels = state.availableModels
        isLoadingModels = state.isLoadingModels
        isRetryingModels = state.isRetryingModels
        modelRetryAttempt = state.modelRetryAttempt
        modelRetryLastError = state.modelRetryLastError
        chatServerErrorMessage = state.chatServerErrorMessage
        lastFetchedModelMetadata = state.lastFetchedModelMetadata
        lastModelFetchEndpoint = state.lastModelFetchEndpoint
    }

    private func applyDetectedModels(_ detection: SettingsModelCatalogDetection) {
        settingsManager.chatModelCapabilities.noteDetectedEndpoint(detection.result.endpoint, for: detection.apiURL)
        settingsManager.chatModelCapabilities.updateImageInputSupport(detection.result.imageInputSupportByModelID, for: detection.apiURL)
        settingsManager.chatModelCapabilities.updateThinkingCapabilities(detection.result.thinkingCapabilitiesByModelID, for: detection.apiURL)

        if let nextSelectedModel = detection.nextSelectedModel {
            selectedModel = nextSelectedModel
        }
    }

    func refreshFromSettingsManager() {
        let s = settingsManager.serverSettings
        let c = settingsManager.chatSettings
        let v = settingsManager.voiceSettings
        let m = settingsManager.modelSettings

        withSuppressed(.autoSaves) {
            serverAddress = s.serverAddress
            textLang = s.textLang

            apiURL = c.apiURL
            selectedModel = c.selectedModel
            chatAPIKey = c.apiKey

            enableStreaming = v.enableStreaming
            hapticFeedbackEnabled = settingsManager.hapticFeedbackEnabled
            apiAdvancedSettings = settingsManager.apiAdvancedSettings

            autoSplit = m.autoSplit
            modelId = m.modelId
            language = m.language
        }

        reloadVoiceServerPresetListAndSelection()
        reloadChatServerPresetListAndSelection()
        reloadPresetListAndSelection()
        loadSelectedPresetFields()
        reloadSystemPromptPresetListsAndSelections()
    }

    private func bindInitialStoreSync() {
        settingsManager.$presets
            .receive(on: RunLoop.main)
            .sink { [weak self] presets in
                guard let self else { return }
                guard !self.didSyncAfterStoreLoad else { return }
                // Presets are only loaded from SwiftData after the model context is attached.
                guard !presets.isEmpty else { return }
                self.didSyncAfterStoreLoad = true
                self.refreshFromSettingsManager()
            }
            .store(in: &cancellables)
    }

    // MARK: - Persist settings

    func saveServerSettings() {
        settingsManager.updateServerSettings(
            serverAddress: serverAddress,
            textLang: textLang
        )
    }

    func saveChatSettings() {
        settingsManager.updateChatSettings(
            apiURL: apiURL,
            selectedModel: selectedModel
        )
    }

    func saveChatAPIKey() {
        settingsManager.updateChatAPIKey(chatAPIKey)
    }

    func saveVoiceSettings() {
        settingsManager.updateVoiceSettings(
            enableStreaming: enableStreaming
        )
    }

    func saveHapticFeedbackSettings() {
        settingsManager.updateHapticFeedbackEnabled(hapticFeedbackEnabled)
    }

    func saveAPIAdvancedSettings() {
        settingsManager.updateAPIAdvancedSettings(apiAdvancedSettings)
    }

    func resetAPIAdvancedSettingsToDefaults() {
        withSuppressed(.autoSaves) {
            apiAdvancedSettings = .defaults
        }
        settingsManager.resetAPIAdvancedSettingsToDefaults()
    }

    func saveModelSettings() {
        settingsManager.updateModelSettings(
            modelId: modelId,
            language: language,
            autoSplit: autoSplit
        )
    }

}
