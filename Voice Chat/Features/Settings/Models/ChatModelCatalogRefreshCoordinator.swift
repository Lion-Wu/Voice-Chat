import Foundation

struct ChatModelCatalogRefreshResult {
    let rawBase: String
    let endpoint: ChatAPIEndpointCandidate
    let models: [ModelInfo]
    let modelIDs: [String]
    let imageInputSupportByModelID: [String: Bool]
    let thinkingCapabilitiesByModelID: [String: ModelThinkingCapability]
}

@MainActor
final class ChatModelCatalogRefreshCoordinator {
    private let modelCatalogFetchCoordinator: ModelCatalogFetchCoordinator
    private(set) var activeRequestID = UUID()
    private var task: Task<ModelCatalogFetchResult?, Never>?

    init(modelCatalogFetchCoordinator: ModelCatalogFetchCoordinator = ModelCatalogFetchCoordinator()) {
        self.modelCatalogFetchCoordinator = modelCatalogFetchCoordinator
    }

    func cancel() {
        activeRequestID = UUID()
        task?.cancel()
        task = nil
    }

    func refresh(
        chatSettings: ChatSettings,
        formatPreference: ChatAPIFormatPreference,
        detectedProvider: ChatProvider?,
        detectedStyle: ChatRequestStyle? = nil
    ) async -> ChatModelCatalogRefreshResult? {
        cancel()
        let rawBase = chatSettings.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawBase.isEmpty else { return nil }

        let requestID = activeRequestID

        let endpointCandidates = modelCatalogFetchCoordinator.modelDetectionCandidates(
            for: rawBase,
            formatPreference: formatPreference,
            detectedProvider: detectedProvider,
            detectedStyle: detectedStyle
        )
        guard !endpointCandidates.isEmpty else { return nil }

        let fetchTask = Task { [modelCatalogFetchCoordinator] in
            try? await modelCatalogFetchCoordinator.fetchFirstAvailableCatalog(
                from: endpointCandidates,
                apiKey: chatSettings.apiKey,
                initialRetryPolicy: ModelCatalogFetchCoordinator.retryPolicy,
                probeRetryPolicy: ModelCatalogFetchCoordinator.retryPolicy,
                onRetry: nil
            )
        }
        task = fetchTask
        let result = await withTaskCancellationHandler {
            await fetchTask.value
        } onCancel: {
            fetchTask.cancel()
        }
        guard activeRequestID == requestID else { return nil }
        task = nil
        guard !Task.isCancelled, let result else { return nil }
        return ChatModelCatalogRefreshResult(
            rawBase: rawBase,
            endpoint: result.endpoint,
            models: result.models,
            modelIDs: result.modelIDs,
            imageInputSupportByModelID: result.imageInputSupportByModelID,
            thinkingCapabilitiesByModelID: result.thinkingCapabilitiesByModelID
        )
    }
}
