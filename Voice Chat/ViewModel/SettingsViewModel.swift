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
    private var suppressLegacySaves = false
    private var didSyncAfterStoreLoad = false

    // MARK: - Legacy settings
    @Published var serverAddress: String { didSet { if !suppressLegacySaves { saveServerSettings() } } }
    @Published var textLang: String { didSet { if !suppressLegacySaves { saveServerSettings() } } }

    // The following legacy fields now live on presets; we keep them for compatibility.
    @Published var refAudioPath_legacy: String { didSet { if !suppressLegacySaves { saveServerSettings() } } }
    @Published var promptText_legacy: String { didSet { if !suppressLegacySaves { saveServerSettings() } } }
    @Published var promptLang_legacy: String { didSet { if !suppressLegacySaves { saveServerSettings() } } }

    @Published var apiURL: String { didSet { if !suppressLegacySaves { saveChatSettings() } } }
    @Published var selectedModel: String { didSet { if !suppressLegacySaves { saveChatSettings() } } }
    @Published var chatAPIKey: String { didSet { if !suppressLegacySaves { saveChatAPIKey() } } }

    @Published var enableStreaming: Bool {
        didSet {
            guard !suppressLegacySaves else { return }
            saveVoiceSettings()
            if enableStreaming {
                // Force `cut0` when streaming is enabled.
                autoSplit = "cut0"
            }
        }
    }

    @Published var autoSplit: String { didSet { if !suppressLegacySaves { saveModelSettings() } } }
    @Published var modelId: String { didSet { if !suppressLegacySaves { saveModelSettings() } } }
    @Published var language: String { didSet { if !suppressLegacySaves { saveModelSettings() } } }

    // MARK: - Model List (Networking)

    @Published private(set) var availableModels: [String] = []
    @Published private(set) var isLoadingModels: Bool = false
    @Published private(set) var isRetryingModels: Bool = false
    @Published private(set) var modelRetryAttempt: Int = 0
    @Published private(set) var modelRetryLastError: String?
    @Published private(set) var chatServerErrorMessage: String?

    private var modelFetchRequestID = UUID()
    private var modelFetchTask: Task<Void, Never>?

    // MARK: - Preset bindings for the UI
    struct PresetSummary: Identifiable, Equatable {
        var id: UUID
        var name: String
    }

    // MARK: - Voice server presets
    @Published var voiceServerPresetList: [PresetSummary] = []
    @Published var selectedVoiceServerPresetID: UUID? {
        didSet {
            if !suppressVoiceServerPresetDidSet {
                settingsManager.selectVoiceServerPreset(selectedVoiceServerPresetID)
                refreshFromSettingsManager()
            }
        }
    }
    @Published var voiceServerPresetName: String = "" { didSet { saveSelectedVoiceServerPresetName() } }

    // MARK: - Chat server presets
    @Published var chatServerPresetList: [PresetSummary] = []
    @Published var selectedChatServerPresetID: UUID? {
        didSet {
            if !suppressChatServerPresetDidSet {
                settingsManager.selectChatServerPreset(selectedChatServerPresetID)
                refreshFromSettingsManager()
            }
        }
    }
    @Published var chatServerPresetName: String = "" { didSet { saveSelectedChatServerPresetName() } }

    @Published var presetList: [PresetSummary] = []
    @Published var selectedPresetID: UUID? {
        didSet {
            if !suppressPresetDidSet {
                SettingsManager.shared.selectPreset(selectedPresetID, apply: true)
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
            if !suppressNormalSystemPromptDidSet {
                SettingsManager.shared.selectNormalSystemPromptPreset(selectedNormalSystemPromptPresetID)
                loadSelectedNormalSystemPromptPresetFields()
            }
        }
    }
    @Published var normalSystemPromptPresetName: String = "" { didSet { saveSelectedNormalSystemPromptPresetName() } }
    @Published var normalSystemPromptPrompt: String = "" { didSet { saveSelectedNormalSystemPromptPresetPrompt() } }

    @Published var voiceSystemPromptPresetList: [PresetSummary] = []
    @Published var selectedVoiceSystemPromptPresetID: UUID? {
        didSet {
            if !suppressVoiceSystemPromptDidSet {
                SettingsManager.shared.selectVoiceSystemPromptPreset(selectedVoiceSystemPromptPresetID)
                loadSelectedVoiceSystemPromptPresetFields()
            }
        }
    }
    @Published var voiceSystemPromptPresetName: String = "" { didSet { saveSelectedVoiceSystemPromptPresetName() } }
    @Published var voiceSystemPromptPrompt: String = "" { didSet { saveSelectedVoiceSystemPromptPresetPrompt() } }

    // MARK: - Dependency
    private let settingsManager = SettingsManager.shared

    // Avoid recursive didSet triggers when swapping presets.
    private var suppressVoiceServerPresetDidSet = false
    private var suppressSaveVoiceServerPreset = false

    private var suppressChatServerPresetDidSet = false
    private var suppressSaveChatServerPreset = false

    private var suppressPresetDidSet = false
    private var suppressSavePreset = false

    private var suppressNormalSystemPromptDidSet = false
    private var suppressSaveNormalSystemPrompt = false
    private var suppressVoiceSystemPromptDidSet = false
    private var suppressSaveVoiceSystemPrompt = false

    // MARK: - Init
    init() {
        // Seed values from the current in-memory state. A later SwiftData attach may update the manager,
        // so we also listen for the first post-load signal and resync.
        serverAddress = ""
        textLang = ""
        refAudioPath_legacy = ""
        promptText_legacy = ""
        promptLang_legacy = "auto"

        apiURL = ""
        selectedModel = ""
        chatAPIKey = ""

        selectedVoiceServerPresetID = nil

        enableStreaming = true

        autoSplit = "cut0"
        modelId = ""
        language = "auto"

        refreshFromSettingsManager()
        bindInitialStoreSync()
    }

    // MARK: - Networking (List Models)

    func fetchAvailableModels() {
        let requestID = UUID()
        modelFetchRequestID = requestID
        modelFetchTask?.cancel()

        isLoadingModels = true
        isRetryingModels = false
        modelRetryAttempt = 0
        modelRetryLastError = nil
        chatServerErrorMessage = nil

        let apiURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiURL.isEmpty else {
            isLoadingModels = false
            chatServerErrorMessage = NSLocalizedString("Server URL is empty or invalid.", comment: "Shown when the model list URL is missing")
            return
        }

        guard let url = buildModelsURL(from: apiURL) else {
            isLoadingModels = false
            chatServerErrorMessage = NSLocalizedString("Invalid Server URL", comment: "Shown when the model list URL cannot be parsed")
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        let rawKey = chatAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawKey.isEmpty {
            let headerValue = rawKey.lowercased().hasPrefix("bearer ") ? rawKey : "Bearer \(rawKey)"
            request.setValue(headerValue, forHTTPHeaderField: "Authorization")
        }

        let retryPolicy = NetworkRetryPolicy(
            maxAttempts: 4,
            baseDelay: 0.5,
            maxDelay: 4.0,
            backoffFactor: 1.6,
            jitterRatio: 0.2
        )

        modelFetchTask = Task { [weak self, request, requestID, retryPolicy] in
            guard let self else { return }
            do {
                let data = try await NetworkRetry.run(
                    policy: retryPolicy,
                    onRetry: { nextAttempt, _, error in
                        await MainActor.run {
                            guard self.modelFetchRequestID == requestID else { return }
                            self.isRetryingModels = true
                            self.modelRetryAttempt = max(1, nextAttempt - 1)
                            self.modelRetryLastError = error.localizedDescription
                        }
                    },
                    operation: {
                        let (data, resp) = try await URLSession.shared.data(for: request)
                        if let http = resp as? HTTPURLResponse,
                           !(200...299).contains(http.statusCode) {
                            let preview = String(data: data, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            let snippet = preview.isEmpty ? nil : String(preview.prefix(180))
                            throw HTTPStatusError(statusCode: http.statusCode, bodyPreview: snippet)
                        }
                        return data
                    }
                )

                let models: [String]
                do {
                    models = try await Task.detached(priority: .utility) { @Sendable in
                        let modelList = try JSONDecoder().decode(ModelListResponse.self, from: data)
                        return modelList.data.map(\.id)
                    }.value
                } catch {
                    guard self.modelFetchRequestID == requestID else { return }
                    self.isLoadingModels = false
                    self.isRetryingModels = false
                    self.modelRetryAttempt = 0
                    self.modelRetryLastError = nil
                    self.chatServerErrorMessage = NSLocalizedString("Unable to parse model list", comment: "Decoding the model list failed")
                    return
                }

                guard self.modelFetchRequestID == requestID else { return }
                self.isLoadingModels = false
                self.isRetryingModels = false
                self.modelRetryAttempt = 0
                self.modelRetryLastError = nil
                self.chatServerErrorMessage = nil

                self.availableModels = models
                if !self.availableModels.contains(self.selectedModel),
                   let firstModel = self.availableModels.first {
                    self.selectedModel = firstModel
                }
            } catch {
                guard self.modelFetchRequestID == requestID else { return }
                self.isLoadingModels = false
                self.isRetryingModels = false
                self.modelRetryAttempt = 0
                self.modelRetryLastError = nil

                if let statusError = error as? HTTPStatusError {
                    self.chatServerErrorMessage = String(
                        format: NSLocalizedString(
                            "Chat server responded with status %d.",
                            comment: "Displayed when the chat server returns an error"
                        ),
                        statusError.statusCode
                    )
                    return
                }

                let message = String(
                    format: NSLocalizedString("Request failed: %@", comment: "Model list request failed"),
                    error.localizedDescription
                )
                self.chatServerErrorMessage = message
            }
        }
    }

    private func buildModelsURL(from base: String) -> URL? {
        var sanitized = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }

        if !sanitized.contains("://") {
            sanitized = "http://\(sanitized)"
        }
        while sanitized.hasSuffix("/") { sanitized.removeLast() }

        guard var comps = URLComponents(string: sanitized) else { return nil }
        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }

        if path.hasSuffix("/v1/models") {
            // Keep as-is.
        } else if path.hasSuffix("/v1/chat/completions") {
            comps.path = String(path.dropLast("/chat/completions".count)) + "/models"
        } else if path.hasSuffix("/v1/chat") {
            comps.path = String(path.dropLast("/chat".count)) + "/models"
        } else if path.hasSuffix("/v1") {
            comps.path = path + "/models"
        } else {
            comps.path = path + "/v1/models"
        }

        return comps.url
    }

    func refreshFromSettingsManager() {
        let s = settingsManager.serverSettings
        let c = settingsManager.chatSettings
        let v = settingsManager.voiceSettings
        let m = settingsManager.modelSettings

        suppressLegacySaves = true
        serverAddress = s.serverAddress
        textLang = s.textLang
        refAudioPath_legacy = s.refAudioPath
        promptText_legacy = s.promptText
        promptLang_legacy = s.promptLang

        apiURL = c.apiURL
        selectedModel = c.selectedModel
        chatAPIKey = c.apiKey

        enableStreaming = v.enableStreaming

        autoSplit = m.autoSplit
        modelId = m.modelId
        language = m.language
        suppressLegacySaves = false

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

    // MARK: - Persist legacy settings

    func saveServerSettings() {
        // Write back the legacy fields so any older callers stay in sync.
        settingsManager.updateServerSettings(
            serverAddress: serverAddress,
            textLang: textLang,
            refAudioPath: refAudioPath_legacy,
            promptText: promptText_legacy,
            promptLang: promptLang_legacy
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

    func saveModelSettings() {
        settingsManager.updateModelSettings(
            modelId: modelId,
            language: language,
            autoSplit: autoSplit
        )
    }

    // MARK: - Voice server preset helpers

    func reloadVoiceServerPresetListAndSelection() {
        voiceServerPresetList = settingsManager.voiceServerPresets.map { .init(id: $0.id, name: $0.name) }
        suppressVoiceServerPresetDidSet = true
        selectedVoiceServerPresetID = settingsManager.selectedVoiceServerPresetID
        suppressVoiceServerPresetDidSet = false
        loadSelectedVoiceServerPresetFields()
    }

    func loadSelectedVoiceServerPresetFields() {
        suppressSaveVoiceServerPreset = true
        defer { suppressSaveVoiceServerPreset = false }

        guard let id = settingsManager.selectedVoiceServerPresetID,
              let p = settingsManager.voiceServerPresets.first(where: { $0.id == id }) else {
            voiceServerPresetName = ""
            return
        }

        voiceServerPresetName = p.name
    }

    private func saveSelectedVoiceServerPresetName() {
        guard !suppressSaveVoiceServerPreset,
              let id = settingsManager.selectedVoiceServerPresetID else { return }
        settingsManager.updateVoiceServerPreset(id: id, name: voiceServerPresetName)
        reloadVoiceServerPresetListAndSelection()
    }

    func addVoiceServerPreset() {
        if let p = settingsManager.createVoiceServerPreset() {
            reloadVoiceServerPresetListAndSelection()
            settingsManager.selectVoiceServerPreset(p.id)
            refreshFromSettingsManager()
        }
    }

    func deleteSelectedVoiceServerPreset() {
        guard let id = settingsManager.selectedVoiceServerPresetID else { return }
        settingsManager.deleteVoiceServerPreset(id)
        refreshFromSettingsManager()
    }

    // MARK: - Chat server preset helpers

    func reloadChatServerPresetListAndSelection() {
        chatServerPresetList = settingsManager.chatServerPresets.map { .init(id: $0.id, name: $0.name) }
        suppressChatServerPresetDidSet = true
        selectedChatServerPresetID = settingsManager.selectedChatServerPresetID
        suppressChatServerPresetDidSet = false
        loadSelectedChatServerPresetFields()
    }

    func loadSelectedChatServerPresetFields() {
        suppressSaveChatServerPreset = true
        defer { suppressSaveChatServerPreset = false }

        guard let id = settingsManager.selectedChatServerPresetID,
              let p = settingsManager.chatServerPresets.first(where: { $0.id == id }) else {
            chatServerPresetName = ""
            return
        }

        chatServerPresetName = p.name
    }

    private func saveSelectedChatServerPresetName() {
        guard !suppressSaveChatServerPreset,
              let id = settingsManager.selectedChatServerPresetID else { return }
        settingsManager.updateChatServerPreset(id: id, name: chatServerPresetName)
        reloadChatServerPresetListAndSelection()
    }

    func addChatServerPreset() {
        if let p = settingsManager.createChatServerPreset() {
            reloadChatServerPresetListAndSelection()
            settingsManager.selectChatServerPreset(p.id)
            refreshFromSettingsManager()
        }
    }

    func deleteSelectedChatServerPreset() {
        guard let id = settingsManager.selectedChatServerPresetID else { return }
        settingsManager.deleteChatServerPreset(id)
        refreshFromSettingsManager()
    }

    // MARK: - Preset helpers

    func reloadPresetListAndSelection() {
        presetList = settingsManager.presets.map { .init(id: $0.id, name: $0.name) }
        suppressPresetDidSet = true
        selectedPresetID = settingsManager.selectedPresetID
        suppressPresetDidSet = false
    }

    func loadSelectedPresetFields() {
        suppressSavePreset = true
        defer { suppressSavePreset = false }

        guard let id = settingsManager.selectedPresetID,
              let p = settingsManager.presets.first(where: { $0.id == id }) else {
            presetName = ""
            presetRefAudioPath = ""
            presetPromptText = ""
            presetPromptLang = "auto"
            presetGPTWeightsPath = ""
            presetSoVITSWeightsPath = ""
            return
        }

        presetName = p.name
        presetRefAudioPath = p.refAudioPath
        presetPromptText = p.promptText
        presetPromptLang = p.promptLang
        presetGPTWeightsPath = p.gptWeightsPath
        presetSoVITSWeightsPath = p.sovitsWeightsPath
    }

    private func savePresetFields() {
        guard !suppressSavePreset, let id = settingsManager.selectedPresetID else { return }
        settingsManager.updatePreset(
            id: id,
            name: presetName,
            refAudioPath: presetRefAudioPath,
            promptText: presetPromptText,
            promptLang: presetPromptLang,
            gptWeightsPath: presetGPTWeightsPath,
            sovitsWeightsPath: presetSoVITSWeightsPath
        )
        // Refresh the list because the preset name may have changed.
        reloadPresetListAndSelection()
    }

    // MARK: - UI operations
    func addPreset() {
        if let p = settingsManager.createPreset() {
            reloadPresetListAndSelection()
            settingsManager.selectPreset(p.id, apply: false)
            reloadPresetListAndSelection()
            loadSelectedPresetFields()
        }
    }

    func deleteCurrentPreset() {
        guard let id = settingsManager.selectedPresetID else { return }
        settingsManager.deletePreset(id)
        reloadPresetListAndSelection()
        loadSelectedPresetFields()
    }

    func applySelectedPresetNow() {
        Task { await settingsManager.applySelectedPreset() }
    }

    // MARK: - System prompt preset helpers

    func reloadSystemPromptPresetListsAndSelections() {
        normalSystemPromptPresetList = settingsManager.normalSystemPromptPresets.map { .init(id: $0.id, name: $0.name) }
        voiceSystemPromptPresetList = settingsManager.voiceSystemPromptPresets.map { .init(id: $0.id, name: $0.name) }

        suppressNormalSystemPromptDidSet = true
        selectedNormalSystemPromptPresetID = settingsManager.selectedNormalSystemPromptPresetID
        suppressNormalSystemPromptDidSet = false
        loadSelectedNormalSystemPromptPresetFields()

        suppressVoiceSystemPromptDidSet = true
        selectedVoiceSystemPromptPresetID = settingsManager.selectedVoiceSystemPromptPresetID
        suppressVoiceSystemPromptDidSet = false
        loadSelectedVoiceSystemPromptPresetFields()
    }

    func loadSelectedNormalSystemPromptPresetFields() {
        suppressSaveNormalSystemPrompt = true
        defer { suppressSaveNormalSystemPrompt = false }

        guard let id = settingsManager.selectedNormalSystemPromptPresetID,
              let p = settingsManager.normalSystemPromptPresets.first(where: { $0.id == id }) else {
            normalSystemPromptPresetName = ""
            normalSystemPromptPrompt = ""
            return
        }

        normalSystemPromptPresetName = p.name
        normalSystemPromptPrompt = p.normalPrompt
    }

    func loadSelectedVoiceSystemPromptPresetFields() {
        suppressSaveVoiceSystemPrompt = true
        defer { suppressSaveVoiceSystemPrompt = false }

        guard let id = settingsManager.selectedVoiceSystemPromptPresetID,
              let p = settingsManager.voiceSystemPromptPresets.first(where: { $0.id == id }) else {
            voiceSystemPromptPresetName = ""
            voiceSystemPromptPrompt = ""
            return
        }

        voiceSystemPromptPresetName = p.name
        voiceSystemPromptPrompt = p.voicePrompt
    }

    private func saveSelectedNormalSystemPromptPresetName() {
        guard !suppressSaveNormalSystemPrompt,
              let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.updateNormalSystemPromptPreset(id: id, name: normalSystemPromptPresetName)
        if let idx = normalSystemPromptPresetList.firstIndex(where: { $0.id == id }) {
            normalSystemPromptPresetList[idx].name = normalSystemPromptPresetName
        }
    }

    private func saveSelectedNormalSystemPromptPresetPrompt() {
        guard !suppressSaveNormalSystemPrompt,
              let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.updateNormalSystemPromptPreset(id: id, prompt: normalSystemPromptPrompt)
    }

    private func saveSelectedVoiceSystemPromptPresetName() {
        guard !suppressSaveVoiceSystemPrompt,
              let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.updateVoiceSystemPromptPreset(id: id, name: voiceSystemPromptPresetName)
        if let idx = voiceSystemPromptPresetList.firstIndex(where: { $0.id == id }) {
            voiceSystemPromptPresetList[idx].name = voiceSystemPromptPresetName
        }
    }

    private func saveSelectedVoiceSystemPromptPresetPrompt() {
        guard !suppressSaveVoiceSystemPrompt,
              let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.updateVoiceSystemPromptPreset(id: id, prompt: voiceSystemPromptPrompt)
    }

    func addNormalSystemPromptPreset() {
        if let p = settingsManager.createNormalSystemPromptPreset() {
            reloadSystemPromptPresetListsAndSelections()
            SettingsManager.shared.selectNormalSystemPromptPreset(p.id)
            reloadSystemPromptPresetListsAndSelections()
        }
    }

    func deleteSelectedNormalSystemPromptPreset() {
        guard let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.deleteSystemPromptPreset(id)
        reloadSystemPromptPresetListsAndSelections()
    }

    func addVoiceSystemPromptPreset() {
        if let p = settingsManager.createVoiceSystemPromptPreset() {
            reloadSystemPromptPresetListsAndSelections()
            SettingsManager.shared.selectVoiceSystemPromptPreset(p.id)
            reloadSystemPromptPresetListsAndSelections()
        }
    }

    func deleteSelectedVoiceSystemPromptPreset() {
        guard let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.deleteSystemPromptPreset(id)
        reloadSystemPromptPresetListsAndSelections()
    }
}
