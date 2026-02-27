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
    private var suppressAutoSaves = false
    private var didSyncAfterStoreLoad = false

    // MARK: - Settings
    @Published var serverAddress: String { didSet { if !suppressAutoSaves { saveServerSettings() } } }
    @Published var textLang: String { didSet { if !suppressAutoSaves { saveServerSettings() } } }

    @Published var apiURL: String { didSet { if !suppressAutoSaves { saveChatSettings() } } }
    @Published var selectedModel: String { didSet { if !suppressAutoSaves { saveChatSettings() } } }
    @Published var chatAPIKey: String { didSet { if !suppressAutoSaves { saveChatAPIKey() } } }

    @Published var enableStreaming: Bool {
        didSet {
            guard !suppressAutoSaves else { return }
            saveVoiceSettings()
            if enableStreaming {
                // Force `cut0` when streaming is enabled.
                autoSplit = "cut0"
            }
        }
    }

    @Published var autoSplit: String {
        didSet {
            guard !suppressAutoSaves else { return }
            saveModelSettings()
        }
    }
    @Published var modelId: String { didSet { if !suppressAutoSaves { saveModelSettings() } } }
    @Published var language: String { didSet { if !suppressAutoSaves { saveModelSettings() } } }
    @Published var hapticFeedbackEnabled: Bool {
        didSet {
            guard !suppressAutoSaves else { return }
            saveHapticFeedbackSettings()
        }
    }

    // MARK: - Model List (Networking)

    @Published private(set) var availableModels: [String] = []
    @Published private(set) var isLoadingModels: Bool = false
    @Published private(set) var isRetryingModels: Bool = false
    @Published private(set) var modelRetryAttempt: Int = 0
    @Published private(set) var modelRetryLastError: String?
    @Published private(set) var chatServerErrorMessage: String?

    private var modelFetchRequestID = UUID()
    private var modelFetchTask: Task<Void, Never>?

    private struct ModelFetchPayload {
        let models: [ModelInfo]
        let rawData: Data
    }

    private struct ModelProbeResult {
        let candidate: ChatAPIEndpointCandidate
        let models: [ModelInfo]
        let score: Int
    }

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

        apiURL = ""
        selectedModel = ""
        chatAPIKey = ""

        selectedVoiceServerPresetID = nil

        enableStreaming = true

        autoSplit = "cut0"
        modelId = ""
        language = "auto"
        hapticFeedbackEnabled = true

        refreshFromSettingsManager()
        bindInitialStoreSync()
    }

    var shouldShowUnknownModelImageInputToggle: Bool {
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return false }
        return settingsManager.isImageInputSupportUnknown(for: model)
    }

    var isSelectedUnknownModelImageInputEnabled: Bool {
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return false }
        return settingsManager.imageInputManualOverride(for: model) == true
    }

    func setSelectedUnknownModelImageInputEnabled(_ enabled: Bool) {
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        // Persist explicit per-model choice for unknown-capability models.
        settingsManager.setImageInputManualOverride(enabled, for: model)
        objectWillChange.send()
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

        let endpointCandidates = ChatAPIEndpointResolver.endpointCandidates(
            for: apiURL,
            preferredProvider: settingsManager.detectedChatProvider(for: apiURL)
        )
        guard !endpointCandidates.isEmpty else {
            isLoadingModels = false
            chatServerErrorMessage = NSLocalizedString("Invalid Server URL", comment: "Shown when the model list URL cannot be parsed")
            return
        }

        let initialRetryPolicy = NetworkRetryPolicy(
            maxAttempts: 2,
            baseDelay: 0.5,
            maxDelay: 4.0,
            backoffFactor: 1.6,
            jitterRatio: 0.2
        )
        let probeRetryPolicy = NetworkRetryPolicy(
            maxAttempts: 1,
            baseDelay: 0.25,
            maxDelay: 1.0,
            backoffFactor: 1.2,
            jitterRatio: 0.1
        )

        modelFetchTask = Task { [weak self, requestID, initialRetryPolicy, probeRetryPolicy, endpointCandidates, apiURL] in
            guard let self else { return }
            var lastError: Error?
            var probes: [ModelProbeResult] = []
            probes.reserveCapacity(endpointCandidates.count)

            for candidate in endpointCandidates {
                guard self.modelFetchRequestID == requestID else { return }
                self.isRetryingModels = false
                self.modelRetryAttempt = 0
                self.modelRetryLastError = nil

                do {
                    let retryPolicy = probes.isEmpty ? initialRetryPolicy : probeRetryPolicy
                    let payload = try await self.requestModels(
                        from: candidate,
                        requestID: requestID,
                        retryPolicy: retryPolicy
                    )
                    let decodedModels = payload.models
                    let score = self.scoreModelsPayload(candidate: candidate, payload: payload)
                    probes.append(ModelProbeResult(candidate: candidate, models: decodedModels, score: score))

                    guard self.modelFetchRequestID == requestID else { return }
                    guard !decodedModels.isEmpty else {
                        let providerName = candidate.provider.displayName
                        let preview = String(
                            format: NSLocalizedString(
                                "No models returned from %@",
                                comment: "Shown when a provider endpoint responds successfully but with an empty models list"
                            ),
                            providerName
                        )
                        lastError = HTTPStatusError(statusCode: 404, bodyPreview: preview)
                        continue
                    }
                } catch {
                    lastError = error
                    continue
                }
            }

            guard self.modelFetchRequestID == requestID else { return }
            self.isLoadingModels = false
            self.isRetryingModels = false
            self.modelRetryAttempt = 0
            self.modelRetryLastError = nil

            if let bestProbe = self.bestProbe(from: probes), !bestProbe.models.isEmpty {
                self.applyDetectedModels(bestProbe.models, from: bestProbe.candidate, apiURL: apiURL)
                return
            }

            if let bestProbe = self.bestProbe(from: probes) {
                self.settingsManager.noteDetectedChatEndpoint(bestProbe.candidate, for: apiURL)
                let providerName = bestProbe.candidate.provider.displayName
                self.chatServerErrorMessage = String(
                    format: NSLocalizedString(
                        "No models returned from %@",
                        comment: "Shown when a provider endpoint responds successfully but with an empty models list"
                    ),
                    providerName
                )
                return
            }

            if let statusError = lastError as? HTTPStatusError {
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
                lastError?.localizedDescription ?? NSLocalizedString("Unknown provider detection error", comment: "Used when provider detection fails without details")
            )
            self.chatServerErrorMessage = message
        }
    }

    private func applyDetectedModels(_ decodedModels: [ModelInfo], from candidate: ChatAPIEndpointCandidate, apiURL: String) {
        isLoadingModels = false
        isRetryingModels = false
        modelRetryAttempt = 0
        modelRetryLastError = nil
        chatServerErrorMessage = nil

        let models = decodedModels.map(\.id)
        var supportMap: [String: Bool] = [:]
        supportMap.reserveCapacity(decodedModels.count)
        for model in decodedModels {
            if let support = model.supportsImageInputHint {
                supportMap[model.id] = support
            }
        }

        settingsManager.noteDetectedChatEndpoint(candidate, for: apiURL)
        settingsManager.updateChatModelImageInputSupport(supportMap)
        availableModels = models
        if !availableModels.contains(selectedModel),
           let firstModel = availableModels.first {
            selectedModel = firstModel
        }
    }

    private func bestProbe(from probes: [ModelProbeResult]) -> ModelProbeResult? {
        probes.max { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            let lhsStyleRank = stylePreferenceRank(lhs.candidate.style)
            let rhsStyleRank = stylePreferenceRank(rhs.candidate.style)
            if lhsStyleRank != rhsStyleRank {
                return lhsStyleRank < rhsStyleRank
            }
            let lhsProviderRank = providerPreferenceRank(lhs.candidate.provider)
            let rhsProviderRank = providerPreferenceRank(rhs.candidate.provider)
            if lhsProviderRank != rhsProviderRank {
                return lhsProviderRank < rhsProviderRank
            }
            return lhs.models.count < rhs.models.count
        }
    }

    private func stylePreferenceRank(_ style: ChatRequestStyle) -> Int {
        switch style {
        case .lmStudioRESTV1:
            return 4
        case .lmStudioRESTV1LegacyMessage:
            return 3
        case .anthropicMessages:
            return 2
        case .openAIChatCompletions:
            return 1
        }
    }

    private func providerPreferenceRank(_ provider: ChatProvider) -> Int {
        switch provider {
        case .lmStudio:
            return 6
        case .anthropic:
            return 5
        case .openAI:
            return 4
        case .llamaCpp:
            return 3
        case .openAICompatible:
            return 2
        case .unknown:
            return 1
        }
    }

    private func scoreModelsPayload(candidate: ChatAPIEndpointCandidate, payload: ModelFetchPayload) -> Int {
        let models = payload.models
        guard !models.isEmpty else { return .min / 4 }

        var score = 1000 + min(models.count, 200)

        var explicitImageMetadataCount = 0
        var richMetadataCount = 0
        for model in models {
            let hasExplicitImageMetadata =
                model.supports_image_input != nil ||
                model.supports_vision != nil ||
                model.vision != nil ||
                model.multimodal != nil
            if hasExplicitImageMetadata {
                explicitImageMetadataCount += 1
            }

            let hasRichMetadata =
                model.capabilities != nil ||
                model.details != nil ||
                model.model_info != nil ||
                model.type != nil ||
                model.arch != nil ||
                (model.input_modalities?.isEmpty == false) ||
                (model.modalities?.isEmpty == false)
            if hasRichMetadata {
                richMetadataCount += 1
            }
        }
        score += explicitImageMetadataCount * 50
        score += richMetadataCount * 16

        let topLevelKeys = topLevelJSONKeys(from: payload.rawData)
        if topLevelKeys.contains("models") {
            score += 320
        }
        if topLevelKeys.contains("data") {
            score += 160
        }
        if topLevelKeys.contains("object") {
            score += 20
        }

        switch candidate.style {
        case .lmStudioRESTV1:
            score += 420
            if !topLevelKeys.contains("models") {
                score -= 80
            }
        case .lmStudioRESTV1LegacyMessage:
            score += 360
            if !topLevelKeys.contains("models") {
                score -= 80
            }
        case .anthropicMessages:
            score += 200
        case .openAIChatCompletions:
            score += 140
        }

        switch candidate.provider {
        case .lmStudio:
            score += 180
        case .anthropic:
            score += 120
        case .openAI:
            score += 100
        case .llamaCpp:
            score += 80
        case .openAICompatible:
            score += 60
        case .unknown:
            break
        }

        return score
    }

    private func topLevelJSONKeys(from data: Data) -> Set<String> {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return []
        }
        return Set(dictionary.keys.map { $0.lowercased() })
    }

    private func normalizedAPIKeyForXAPIKeyHeader(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func applyModelRequestHeaders(
        to request: inout URLRequest,
        candidate: ChatAPIEndpointCandidate,
        rawAPIKey: String
    ) {
        switch candidate.style {
        case .anthropicMessages:
            let xAPIKey = normalizedAPIKeyForXAPIKeyHeader(rawAPIKey)
            if !xAPIKey.isEmpty {
                request.setValue(xAPIKey, forHTTPHeaderField: "x-api-key")
            }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        case .openAIChatCompletions, .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            let trimmed = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let headerValue = trimmed.lowercased().hasPrefix("bearer ") ? trimmed : "Bearer \(trimmed)"
                request.setValue(headerValue, forHTTPHeaderField: "Authorization")
            }
        }
    }

    private func requestModels(
        from candidate: ChatAPIEndpointCandidate,
        requestID: UUID,
        retryPolicy: NetworkRetryPolicy
    ) async throws -> ModelFetchPayload {
        var mutableRequest = URLRequest(url: candidate.modelsURL, timeoutInterval: 30)
        mutableRequest.httpMethod = "GET"
        let rawAPIKey = chatAPIKey
        applyModelRequestHeaders(to: &mutableRequest, candidate: candidate, rawAPIKey: rawAPIKey)
        let request = mutableRequest

        let data = try await NetworkRetry.run(
            policy: retryPolicy,
            onRetry: { [weak self] nextAttempt, _, error in
                guard let self else { return }
                await MainActor.run {
                    guard self.modelFetchRequestID == requestID else { return }
                    self.isRetryingModels = true
                    self.modelRetryAttempt = max(1, nextAttempt - 1)
                    self.modelRetryLastError = "\(candidate.provider.displayName): \(error.localizedDescription)"
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

        let decodedModels: [ModelInfo] = try await Task.detached(priority: .utility) { @Sendable in
            let modelList = try JSONDecoder().decode(ModelListResponse.self, from: data)
            return modelList.data
        }.value
        return ModelFetchPayload(models: decodedModels, rawData: data)
    }

    func refreshFromSettingsManager() {
        let s = settingsManager.serverSettings
        let c = settingsManager.chatSettings
        let v = settingsManager.voiceSettings
        let m = settingsManager.modelSettings

        suppressAutoSaves = true
        serverAddress = s.serverAddress
        textLang = s.textLang

        apiURL = c.apiURL
        selectedModel = c.selectedModel
        chatAPIKey = c.apiKey

        enableStreaming = v.enableStreaming
        hapticFeedbackEnabled = settingsManager.hapticFeedbackEnabled

        autoSplit = m.autoSplit
        modelId = m.modelId
        language = m.language
        suppressAutoSaves = false

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
            AppHaptics.trigger(.success)
        }
    }

    func deleteSelectedVoiceServerPreset() {
        guard let id = settingsManager.selectedVoiceServerPresetID else { return }
        settingsManager.deleteVoiceServerPreset(id)
        refreshFromSettingsManager()
        AppHaptics.trigger(.warning)
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
            AppHaptics.trigger(.success)
        }
    }

    func deleteSelectedChatServerPreset() {
        guard let id = settingsManager.selectedChatServerPresetID else { return }
        settingsManager.deleteChatServerPreset(id)
        refreshFromSettingsManager()
        AppHaptics.trigger(.warning)
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
            AppHaptics.trigger(.success)
        }
    }

    func deleteCurrentPreset() {
        guard let id = settingsManager.selectedPresetID else { return }
        settingsManager.deletePreset(id)
        reloadPresetListAndSelection()
        loadSelectedPresetFields()
        AppHaptics.trigger(.warning)
    }

    func applySelectedPresetNow() {
        AppHaptics.trigger(.selection)
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
            AppHaptics.trigger(.success)
        }
    }

    func deleteSelectedNormalSystemPromptPreset() {
        guard let id = settingsManager.selectedNormalSystemPromptPresetID else { return }
        settingsManager.deleteSystemPromptPreset(id)
        reloadSystemPromptPresetListsAndSelections()
        AppHaptics.trigger(.warning)
    }

    func addVoiceSystemPromptPreset() {
        if let p = settingsManager.createVoiceSystemPromptPreset() {
            reloadSystemPromptPresetListsAndSelections()
            SettingsManager.shared.selectVoiceSystemPromptPreset(p.id)
            reloadSystemPromptPresetListsAndSelections()
            AppHaptics.trigger(.success)
        }
    }

    func deleteSelectedVoiceSystemPromptPreset() {
        guard let id = settingsManager.selectedVoiceSystemPromptPresetID else { return }
        settingsManager.deleteSystemPromptPreset(id)
        reloadSystemPromptPresetListsAndSelections()
        AppHaptics.trigger(.warning)
    }
}
