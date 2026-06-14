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
    private var activeRequestID = UUID()

    private static let retryPolicy = NetworkRetryPolicy(
        maxAttempts: 1,
        baseDelay: 0,
        maxDelay: 0,
        backoffFactor: 1,
        jitterRatio: 0
    )

    init(modelCatalogFetchCoordinator: ModelCatalogFetchCoordinator = ModelCatalogFetchCoordinator()) {
        self.modelCatalogFetchCoordinator = modelCatalogFetchCoordinator
    }

    func refresh(
        chatSettings: ChatSettings,
        formatPreference: ChatAPIFormatPreference,
        detectedProvider: ChatProvider?
    ) async -> ChatModelCatalogRefreshResult? {
        let rawBase = chatSettings.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawBase.isEmpty else { return nil }

        let requestID = UUID()
        activeRequestID = requestID

        let endpointCandidates = modelCatalogFetchCoordinator.modelDetectionCandidates(
            for: rawBase,
            formatPreference: formatPreference,
            detectedProvider: detectedProvider
        )
        guard !endpointCandidates.isEmpty else { return nil }

        guard let result = try? await modelCatalogFetchCoordinator.fetchFirstAvailableCatalog(
            from: endpointCandidates,
            apiKey: chatSettings.apiKey,
            initialRetryPolicy: Self.retryPolicy,
            probeRetryPolicy: Self.retryPolicy,
            onRetry: nil
        ) else {
            return nil
        }

        guard activeRequestID == requestID else { return nil }
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
