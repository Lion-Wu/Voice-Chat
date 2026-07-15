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

typealias ModelCatalogDataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

enum ModelCatalogPaginationError: LocalizedError, Equatable {
    case missingCursor
    case repeatedCursor(String)

    var errorDescription: String? {
        switch self {
        case .missingCursor:
            return "The model catalog reported another page without a cursor."
        case let .repeatedCursor(cursor):
            return "The model catalog repeated pagination cursor \(cursor)."
        }
    }
}

struct DefaultModelCatalogService: ModelCatalogFetching, Sendable {
    private let dataLoader: ModelCatalogDataLoader

    init(
        dataLoader: @escaping ModelCatalogDataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.dataLoader = dataLoader
    }

    func fetchModels(
        from candidate: ChatAPIEndpointCandidate,
        apiKey: String,
        retryPolicy: NetworkRetryPolicy,
        onRetry: (@Sendable (_ nextAttempt: Int, _ delay: TimeInterval, _ error: Error) async -> Void)? = nil
    ) async throws -> [ModelInfo] {
        var pageURL = candidate.modelsURL
        var models: [ModelInfo] = []
        var seenModelIDs = Set<String>()
        var seenCursors = Set<String>()

        while true {
            try Task.checkCancellation()
            var request = URLRequest(url: pageURL, timeoutInterval: 30)
            request.httpMethod = "GET"
            applyModelRequestHeaders(to: &request, candidate: candidate, rawAPIKey: apiKey)
            let immutableRequest = request

            let data = try await NetworkRetry.run(
                policy: retryPolicy,
                onRetry: onRetry,
                operation: {
                    let (data, response) = try await dataLoader(immutableRequest)
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

            let page = try await Task.detached(priority: .utility) { @Sendable in
                try JSONDecoder().decode(ModelListResponse.self, from: data)
            }.value
            for model in page.data where seenModelIDs.insert(model.id).inserted {
                models.append(model)
            }

            guard candidate.style == .anthropicMessages, page.hasMore == true else {
                return models
            }
            let cursor = page.lastID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cursor.isEmpty else {
                throw ModelCatalogPaginationError.missingCursor
            }
            guard seenCursors.insert(cursor).inserted else {
                throw ModelCatalogPaginationError.repeatedCursor(cursor)
            }
            pageURL = try Self.paginationURL(afterID: cursor, baseURL: candidate.modelsURL)
        }
    }

    static func paginationURL(afterID: String, baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ChatNetworkError.invalidURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "after_id" }
        queryItems.append(URLQueryItem(name: "after_id", value: afterID))
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ChatNetworkError.invalidURL
        }
        return url
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
            let trimmed = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if usesBearerAuthForAnthropicMessages(candidate.modelsURL) {
                if !trimmed.isEmpty {
                    let headerValue = trimmed.lowercased().hasPrefix("bearer ") ? trimmed : "Bearer \(trimmed)"
                    request.setValue(headerValue, forHTTPHeaderField: "Authorization")
                }
            } else {
                let xAPIKey = normalizedAPIKeyForXAPIKeyHeader(trimmed)
                if !xAPIKey.isEmpty {
                    request.setValue(xAPIKey, forHTTPHeaderField: "x-api-key")
                }
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }

        case .openAIResponses, .openAIChatCompletions, .lmStudioRESTV1:
            let trimmed = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if usesAzureOpenAIAPIKeyAuth(candidate.modelsURL, rawAPIKey: trimmed) {
                    request.setValue(normalizedAPIKeyForXAPIKeyHeader(trimmed), forHTTPHeaderField: "api-key")
                } else {
                    let headerValue = trimmed.lowercased().hasPrefix("bearer ") ? trimmed : "Bearer \(trimmed)"
                    request.setValue(headerValue, forHTTPHeaderField: "Authorization")
                }
            }
        }
    }

    private func usesBearerAuthForAnthropicMessages(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "openrouter.ai")
    }

    private func usesAzureOpenAIAPIKeyAuth(_ url: URL, rawAPIKey: String) -> Bool {
        let host = (url.host ?? "").lowercased()
        return ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "openai.azure.com") &&
            !rawAPIKey.lowercased().hasPrefix("bearer ")
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
