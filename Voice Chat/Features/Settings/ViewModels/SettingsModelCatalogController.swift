//
//  SettingsModelCatalogController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct SettingsModelCatalogState {
    var availableModels: [String]
    var isLoadingModels: Bool
    var isRetryingModels: Bool
    var modelRetryAttempt: Int
    var modelRetryLastError: String?
    var chatServerErrorMessage: String?
    var lastFetchedModelMetadata: [ModelInfo]
    var lastModelFetchEndpoint: ChatAPIEndpointCandidate?

    static func loading(from current: SettingsModelCatalogState) -> SettingsModelCatalogState {
        SettingsModelCatalogState(
            availableModels: current.availableModels,
            isLoadingModels: true,
            isRetryingModels: false,
            modelRetryAttempt: 0,
            modelRetryLastError: nil,
            chatServerErrorMessage: nil,
            lastFetchedModelMetadata: current.lastFetchedModelMetadata,
            lastModelFetchEndpoint: current.lastModelFetchEndpoint
        )
    }

    static func validationFailure(
        from current: SettingsModelCatalogState,
        message: String
    ) -> SettingsModelCatalogState {
        SettingsModelCatalogState(
            availableModels: current.availableModels,
            isLoadingModels: false,
            isRetryingModels: false,
            modelRetryAttempt: 0,
            modelRetryLastError: nil,
            chatServerErrorMessage: message,
            lastFetchedModelMetadata: current.lastFetchedModelMetadata,
            lastModelFetchEndpoint: current.lastModelFetchEndpoint
        )
    }

    static func retrying(
        from current: SettingsModelCatalogState,
        candidate: ChatAPIEndpointCandidate,
        nextAttempt: Int,
        error: Error
    ) -> SettingsModelCatalogState {
        SettingsModelCatalogState(
            availableModels: current.availableModels,
            isLoadingModels: current.isLoadingModels,
            isRetryingModels: true,
            modelRetryAttempt: max(1, nextAttempt - 1),
            modelRetryLastError: "\(candidate.provider.displayName): \(error.localizedDescription)",
            chatServerErrorMessage: current.chatServerErrorMessage,
            lastFetchedModelMetadata: current.lastFetchedModelMetadata,
            lastModelFetchEndpoint: current.lastModelFetchEndpoint
        )
    }

    static func detected(
        from current: SettingsModelCatalogState,
        result: ModelCatalogFetchResult
    ) -> SettingsModelCatalogState {
        let emptyModelsMessage: String?
        if result.models.isEmpty {
            emptyModelsMessage = String(
                format: NSLocalizedString(
                    "No models returned from %@",
                    comment: "Shown when a provider endpoint responds successfully but with an empty models list"
                ),
                result.endpoint.provider.displayName
            )
        } else {
            emptyModelsMessage = nil
        }

        return SettingsModelCatalogState(
            availableModels: result.modelIDs,
            isLoadingModels: false,
            isRetryingModels: false,
            modelRetryAttempt: 0,
            modelRetryLastError: nil,
            chatServerErrorMessage: emptyModelsMessage,
            lastFetchedModelMetadata: result.models,
            lastModelFetchEndpoint: result.endpoint
        )
    }

    static func failure(
        from current: SettingsModelCatalogState,
        error: Error
    ) -> SettingsModelCatalogState {
        let underlyingError = (error as? ModelCatalogFetchError)?.lastError ?? error
        let message: String
        if let statusError = underlyingError as? HTTPStatusError {
            message = String(
                format: NSLocalizedString(
                    "Chat server responded with status %d.",
                    comment: "Displayed when the chat server returns an error"
                ),
                statusError.statusCode
            )
        } else {
            message = String(
                format: NSLocalizedString("Request failed: %@", comment: "Model list request failed"),
                underlyingError.localizedDescription
            )
        }

        return SettingsModelCatalogState(
            availableModels: current.availableModels,
            isLoadingModels: false,
            isRetryingModels: false,
            modelRetryAttempt: 0,
            modelRetryLastError: nil,
            chatServerErrorMessage: message,
            lastFetchedModelMetadata: current.lastFetchedModelMetadata,
            lastModelFetchEndpoint: current.lastModelFetchEndpoint
        )
    }
}

struct SettingsModelCatalogRequest {
    var apiURL: String
    var apiKey: String
    var formatPreference: ChatAPIFormatPreference
    var detectedProvider: ChatProvider?
    var selectedModel: String
}

struct SettingsModelCatalogDetection {
    var apiURL: String
    var result: ModelCatalogFetchResult
    var nextSelectedModel: String?
}

@MainActor
final class SettingsModelCatalogController {
    private let modelCatalogFetchCoordinator: ModelCatalogFetchCoordinator
    private var activeRequestID = UUID()
    private var task: Task<Void, Never>?

    init(modelCatalogFetchCoordinator: ModelCatalogFetchCoordinator = ModelCatalogFetchCoordinator()) {
        self.modelCatalogFetchCoordinator = modelCatalogFetchCoordinator
    }

    func fetch(
        request: SettingsModelCatalogRequest,
        currentState: SettingsModelCatalogState,
        applyState: @escaping @MainActor (SettingsModelCatalogState) -> Void,
        applyDetection: @escaping @MainActor (SettingsModelCatalogDetection) -> Void
    ) {
        let requestID = UUID()
        activeRequestID = requestID
        task?.cancel()

        let loadingState = SettingsModelCatalogState.loading(from: currentState)
        applyState(loadingState)

        let apiURL = request.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiURL.isEmpty else {
            applyState(SettingsModelCatalogState.validationFailure(
                from: loadingState,
                message: NSLocalizedString(
                    "Server URL is empty or invalid.",
                    comment: "Shown when the model list URL is missing"
                )
            ))
            return
        }

        let endpointCandidates = modelCatalogFetchCoordinator.modelDetectionCandidates(
            for: apiURL,
            formatPreference: request.formatPreference,
            detectedProvider: request.detectedProvider
        )
        guard !endpointCandidates.isEmpty else {
            applyState(SettingsModelCatalogState.validationFailure(
                from: loadingState,
                message: NSLocalizedString(
                    "Invalid Server URL",
                    comment: "Shown when the model list URL cannot be parsed"
                )
            ))
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

        task = Task { [weak self, requestID, endpointCandidates, apiURL, request, loadingState, initialRetryPolicy, probeRetryPolicy] in
            guard let self else { return }
            do {
                let result = try await self.modelCatalogFetchCoordinator.fetchFirstAvailableCatalog(
                    from: endpointCandidates,
                    apiKey: request.apiKey,
                    initialRetryPolicy: initialRetryPolicy,
                    probeRetryPolicy: probeRetryPolicy,
                    onRetry: { [weak self, requestID, loadingState] candidate, nextAttempt, _, error in
                        await MainActor.run {
                            guard let self, self.activeRequestID == requestID else { return }
                            applyState(SettingsModelCatalogState.retrying(
                                from: loadingState,
                                candidate: candidate,
                                nextAttempt: nextAttempt,
                                error: error
                            ))
                        }
                    }
                )

                guard activeRequestID == requestID else { return }
                applyState(SettingsModelCatalogState.detected(from: loadingState, result: result))
                applyDetection(SettingsModelCatalogDetection(
                    apiURL: apiURL,
                    result: result,
                    nextSelectedModel: Self.nextSelectedModel(
                        currentSelectedModel: request.selectedModel,
                        availableModels: result.modelIDs
                    )
                ))
            } catch {
                guard activeRequestID == requestID else { return }
                applyState(SettingsModelCatalogState.failure(from: loadingState, error: error))
            }
        }
    }

    private static func nextSelectedModel(
        currentSelectedModel: String,
        availableModels: [String]
    ) -> String? {
        if !availableModels.contains(currentSelectedModel),
           let firstModel = availableModels.first {
            return firstModel
        }
        return nil
    }
}
