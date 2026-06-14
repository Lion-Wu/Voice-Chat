//
//  ModelCatalogService.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

protocol ModelCatalogFetching: Sendable {
    func fetchModels(
        from candidate: ChatAPIEndpointCandidate,
        apiKey: String,
        retryPolicy: NetworkRetryPolicy,
        onRetry: (@Sendable (_ nextAttempt: Int, _ delay: TimeInterval, _ error: Error) async -> Void)?
    ) async throws -> [ModelInfo]
}

struct DefaultModelCatalogService: ModelCatalogFetching, Sendable {
    func fetchModels(
        from candidate: ChatAPIEndpointCandidate,
        apiKey: String,
        retryPolicy: NetworkRetryPolicy,
        onRetry: (@Sendable (_ nextAttempt: Int, _ delay: TimeInterval, _ error: Error) async -> Void)? = nil
    ) async throws -> [ModelInfo] {
        var mutableRequest = URLRequest(url: candidate.modelsURL, timeoutInterval: 30)
        mutableRequest.httpMethod = "GET"
        applyModelRequestHeaders(to: &mutableRequest, candidate: candidate, rawAPIKey: apiKey)
        let request = mutableRequest

        let data = try await NetworkRetry.run(
            policy: retryPolicy,
            onRetry: onRetry,
            operation: {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    let preview = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let snippet = preview.isEmpty ? nil : String(preview.prefix(180))
                    throw HTTPStatusError(statusCode: http.statusCode, bodyPreview: snippet)
                }
                return data
            }
        )

        return try await Task.detached(priority: .utility) { @Sendable in
            try JSONDecoder().decode(ModelListResponse.self, from: data).data
        }.value
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
}

struct ModelCatalogFetchResult {
    let endpoint: ChatAPIEndpointCandidate
    let models: [ModelInfo]

    var modelIDs: [String] {
        models.map(\.id)
    }

    var imageInputSupportByModelID: [String: Bool] {
        var supportMap: [String: Bool] = [:]
        supportMap.reserveCapacity(models.count)
        for model in models {
            if let support = model.supportsImageInputHint {
                supportMap[model.id] = support
            }
        }
        return supportMap
    }

    var thinkingCapabilitiesByModelID: [String: ModelThinkingCapability] {
        var thinkingMap: [String: ModelThinkingCapability] = [:]
        thinkingMap.reserveCapacity(models.count)
        for model in models {
            if let thinking = model.thinkingCapabilityHint(provider: endpoint.provider, requestStyle: endpoint.style) {
                thinkingMap[model.id] = thinking
            }
        }
        return thinkingMap
    }
}

enum ModelCatalogFetchError: Error {
    case allCandidatesFailed(Error?)

    var lastError: Error? {
        switch self {
        case let .allCandidatesFailed(error):
            return error
        }
    }
}

struct ModelCatalogFetchCoordinator {
    private let modelCatalogService: ModelCatalogFetching

    init(modelCatalogService: ModelCatalogFetching = DefaultModelCatalogService()) {
        self.modelCatalogService = modelCatalogService
    }

    func modelDetectionCandidates(
        for apiURL: String,
        formatPreference: ChatAPIFormatPreference,
        detectedProvider: ChatProvider?
    ) -> [ChatAPIEndpointCandidate] {
        if formatPreference != .automatic {
            if let forced = ChatAPIEndpointResolver.endpointCandidate(for: apiURL, formatPreference: formatPreference) {
                return [forced]
            }
            return []
        }

        if let official = ChatAPIEndpointResolver.officialProviderHint(for: apiURL),
           let pinned = ChatAPIEndpointResolver.endpointCandidate(for: apiURL, provider: official) {
            return [pinned]
        }

        return ChatAPIEndpointResolver.autoDetectionCandidates(
            for: apiURL,
            preferredProvider: detectedProvider
        )
    }

    func fetchFirstAvailableCatalog(
        from endpointCandidates: [ChatAPIEndpointCandidate],
        apiKey: String,
        initialRetryPolicy: NetworkRetryPolicy,
        probeRetryPolicy: NetworkRetryPolicy,
        onRetry: (@Sendable (
            _ candidate: ChatAPIEndpointCandidate,
            _ nextAttempt: Int,
            _ delay: TimeInterval,
            _ error: Error
        ) async -> Void)?
    ) async throws -> ModelCatalogFetchResult {
        var lastError: Error?

        for (index, candidate) in endpointCandidates.enumerated() {
            do {
                let retryPolicy = index == 0 ? initialRetryPolicy : probeRetryPolicy
                let models = try await modelCatalogService.fetchModels(
                    from: candidate,
                    apiKey: apiKey,
                    retryPolicy: retryPolicy,
                    onRetry: { nextAttempt, delay, error in
                        await onRetry?(candidate, nextAttempt, delay, error)
                    }
                )
                return ModelCatalogFetchResult(endpoint: candidate, models: models)
            } catch {
                if NetworkRetryability.isCancellation(error) {
                    throw error
                }
                lastError = error
                continue
            }
        }

        throw ModelCatalogFetchError.allCandidatesFailed(lastError)
    }
}
