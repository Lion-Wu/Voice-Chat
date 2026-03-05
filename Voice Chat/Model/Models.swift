//
//  Models.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//

import Foundation

enum ChatProvider: String, Codable, Sendable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case lmStudio = "lmstudio"
    case llamaCpp = "llama.cpp"
    case openAICompatible = "openai-compatible"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .openAI:
            return NSLocalizedString("OpenAI", comment: "Provider display name")
        case .anthropic:
            return NSLocalizedString("Anthropic", comment: "Provider display name")
        case .lmStudio:
            return NSLocalizedString("LM Studio", comment: "Provider display name")
        case .llamaCpp:
            return NSLocalizedString("llama.cpp", comment: "Provider display name")
        case .openAICompatible:
            return NSLocalizedString("OpenAI Compatible", comment: "Provider display name")
        case .unknown:
            return NSLocalizedString("Unknown", comment: "Provider display name")
        }
    }
}

enum ChatRequestStyle: String, Codable, Sendable {
    case openAIChatCompletions
    case lmStudioRESTV1
    case lmStudioRESTV1LegacyMessage
    case anthropicMessages
}

enum ChatAPIFormatPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case openAI
    case anthropic
    case lmStudio
    case llamaCpp
    case openAICompatible

    var providerHint: ChatProvider? {
        switch self {
        case .automatic:
            return nil
        case .openAI:
            return .openAI
        case .anthropic:
            return .anthropic
        case .lmStudio:
            return .lmStudio
        case .llamaCpp:
            return .llamaCpp
        case .openAICompatible:
            return .openAICompatible
        }
    }

    var requestStyleHint: ChatRequestStyle? {
        switch self {
        case .automatic:
            return nil
        case .openAI, .llamaCpp, .openAICompatible:
            return .openAIChatCompletions
        case .anthropic:
            return .anthropicMessages
        case .lmStudio:
            return .lmStudioRESTV1
        }
    }
}

struct ChatAPIEndpointCandidate: Hashable, Sendable {
    let provider: ChatProvider
    let style: ChatRequestStyle
    let chatURL: URL
    let modelsURL: URL
}

enum ChatAPIEndpointResolver {
    static func officialProviderHint(for base: String) -> ChatProvider? {
        guard let comps = normalizedComponents(from: base) else { return nil }
        let host = (comps.host ?? "").lowercased()

        if hostMatchesOfficialDomain(host, domain: "openai.com") {
            return .openAI
        }
        if hostMatchesOfficialDomain(host, domain: "anthropic.com") {
            return .anthropic
        }
        return nil
    }

    static func endpointCandidate(
        for base: String,
        formatPreference: ChatAPIFormatPreference
    ) -> ChatAPIEndpointCandidate? {
        guard let provider = formatPreference.providerHint else { return nil }
        return endpointCandidate(
            for: base,
            provider: provider,
            preferredStyle: formatPreference.requestStyleHint
        )
    }

    static func endpointCandidate(
        for base: String,
        provider: ChatProvider,
        preferredStyle: ChatRequestStyle? = nil
    ) -> ChatAPIEndpointCandidate? {
        guard let comps = normalizedComponents(from: base) else { return nil }
        var candidates: [ChatAPIEndpointCandidate] = []
        appendCandidates(for: provider, base: comps, to: &candidates)
        guard !candidates.isEmpty else { return nil }

        if let preferredStyle,
           let preferred = candidates.first(where: { $0.style == preferredStyle }) {
            return preferred
        }
        return candidates.first
    }

    static func autoDetectionCandidates(
        for base: String,
        preferredProvider: ChatProvider? = nil
    ) -> [ChatAPIEndpointCandidate] {
        guard let comps = normalizedComponents(from: base) else { return [] }
        let path = canonicalPath(comps.path).lowercased()
        let host = (comps.host ?? "").lowercased()
        let port = comps.port
        let isLocal = isLocalHost(host)
        let looksLlamaCpp = host.contains("llama") || path.contains("llama.cpp") || (isLocal && (port == 8080 || port == 8081))

        if let official = officialProviderHint(for: base),
           let pinned = endpointCandidate(for: base, provider: official) {
            return [pinned]
        }

        var candidates: [ChatAPIEndpointCandidate] = []
        candidates.reserveCapacity(4)

        func appendUnique(_ candidate: ChatAPIEndpointCandidate?) {
            guard let candidate else { return }
            if candidates.contains(where: { $0.style == candidate.style && $0.chatURL == candidate.chatURL }) {
                return
            }
            candidates.append(candidate)
        }

        appendUnique(endpointCandidate(for: base, provider: .lmStudio, preferredStyle: .lmStudioRESTV1))
        appendUnique(endpointCandidate(for: base, provider: .lmStudio, preferredStyle: .lmStudioRESTV1LegacyMessage))

        if isLocal || looksLlamaCpp {
            appendUnique(endpointCandidate(for: base, provider: .llamaCpp, preferredStyle: .openAIChatCompletions))
        }

        appendUnique(endpointCandidate(for: base, provider: .openAICompatible, preferredStyle: .openAIChatCompletions))

        if candidates.isEmpty {
            var fallback = endpointCandidates(for: base, preferredProvider: preferredProvider)
            if let preferredProvider {
                let preferredOnly = fallback.filter { $0.provider == preferredProvider }
                if !preferredOnly.isEmpty {
                    fallback = preferredOnly
                }
            }
            return fallback
        }

        return candidates
    }

    static func normalizedAPIBaseKey(_ base: String) -> String? {
        guard var comps = normalizedComponents(from: base) else { return nil }
        comps.path = canonicalPath(comps.path)
        return comps.url?.absoluteString.lowercased()
    }

    static func endpointCandidates(for base: String, preferredProvider: ChatProvider? = nil) -> [ChatAPIEndpointCandidate] {
        guard let comps = normalizedComponents(from: base) else { return [] }
        let path = canonicalPath(comps.path).lowercased()
        let host = (comps.host ?? "").lowercased()
        let port = comps.port

        let order = providerOrder(path: path, host: host, port: port, preferred: preferredProvider)

        var candidates: [ChatAPIEndpointCandidate] = []
        candidates.reserveCapacity(order.count + 2)

        for provider in order {
            appendCandidates(for: provider, base: comps, to: &candidates)
        }
        return candidates
    }

    private static func providerOrder(path: String, host: String, port: Int?, preferred: ChatProvider?) -> [ChatProvider] {
        var order: [ChatProvider] = []

        func append(_ provider: ChatProvider) {
            guard !order.contains(provider) else { return }
            order.append(provider)
        }

        let isLocal = isLocalHost(host)
        let looksAnthropic = host.contains("anthropic.com") || path.hasSuffix("/v1/messages")
        let looksOpenAI = host.contains("openai.com")
        let looksLMStudio = host.contains("lmstudio") || path.contains("/api/v1") || path.contains("/api/v0") || (isLocal && (port == 1234))
        let looksLlamaCpp = host.contains("llama") || path.contains("llama.cpp") || (isLocal && (port == 8080 || port == 8081))

        var heuristicOrder: [ChatProvider] = []
        func appendHeuristic(_ provider: ChatProvider) {
            guard !heuristicOrder.contains(provider) else { return }
            heuristicOrder.append(provider)
        }

        if looksAnthropic {
            appendHeuristic(.anthropic)
        }
        if looksLMStudio {
            appendHeuristic(.lmStudio)
        }
        if looksOpenAI {
            appendHeuristic(.openAI)
        }
        if looksLlamaCpp {
            appendHeuristic(.llamaCpp)
        }

        if !heuristicOrder.isEmpty {
            heuristicOrder.forEach(append)
            if let preferred, preferred != .unknown, !heuristicOrder.contains(preferred) {
                append(preferred)
            }
        } else {
            if let preferred, preferred != .unknown {
                append(preferred)
            }
            append(.lmStudio)
            append(.llamaCpp)
            append(.openAICompatible)
            if !isLocal {
                // Keep explicit cloud providers as later fallbacks for non-local endpoints.
                append(.openAI)
                append(.anthropic)
            }
        }

        append(.lmStudio)
        append(.llamaCpp)
        append(.openAICompatible)
        append(.openAI)
        append(.anthropic)

        return order
    }

    private static func appendCandidates(
        for provider: ChatProvider,
        base: URLComponents,
        to list: inout [ChatAPIEndpointCandidate]
    ) {
        switch provider {
        case .lmStudio:
            if let urls = lmStudioURLs(from: base) {
                appendUnique(
                    ChatAPIEndpointCandidate(
                        provider: .lmStudio,
                        style: .lmStudioRESTV1,
                        chatURL: urls.chat,
                        modelsURL: urls.models
                    ),
                    to: &list
                )
            }
            if let urls = openAICompatibleURLs(from: base) {
                appendUnique(
                    ChatAPIEndpointCandidate(
                        provider: .lmStudio,
                        style: .openAIChatCompletions,
                        chatURL: urls.chat,
                        modelsURL: urls.models
                    ),
                    to: &list
                )
            }

        case .anthropic:
            if let urls = anthropicURLs(from: base) {
                appendUnique(
                    ChatAPIEndpointCandidate(
                        provider: .anthropic,
                        style: .anthropicMessages,
                        chatURL: urls.chat,
                        modelsURL: urls.models
                    ),
                    to: &list
                )
            }

        case .llamaCpp:
            if let urls = openAICompatibleURLs(from: base) {
                appendUnique(
                    ChatAPIEndpointCandidate(
                        provider: .llamaCpp,
                        style: .openAIChatCompletions,
                        chatURL: urls.chat,
                        modelsURL: urls.models
                    ),
                    to: &list
                )
            }

        case .openAI:
            if let urls = openAICompatibleURLs(from: base) {
                appendUnique(
                    ChatAPIEndpointCandidate(
                        provider: .openAI,
                        style: .openAIChatCompletions,
                        chatURL: urls.chat,
                        modelsURL: urls.models
                    ),
                    to: &list
                )
            }

        case .openAICompatible, .unknown:
            if let urls = openAICompatibleURLs(from: base) {
                appendUnique(
                    ChatAPIEndpointCandidate(
                        provider: .openAICompatible,
                        style: .openAIChatCompletions,
                        chatURL: urls.chat,
                        modelsURL: urls.models
                    ),
                    to: &list
                )
            }
        }
    }

    private static func appendUnique(_ candidate: ChatAPIEndpointCandidate, to list: inout [ChatAPIEndpointCandidate]) {
        if list.contains(where: { $0.style == candidate.style && $0.chatURL == candidate.chatURL }) {
            return
        }
        list.append(candidate)
    }

    private static func normalizedComponents(from base: String) -> URLComponents? {
        var sanitized = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }

        if !sanitized.contains("://") {
            sanitized = "http://\(sanitized)"
        }
        while sanitized.hasSuffix("/") {
            sanitized.removeLast()
        }
        return URLComponents(string: sanitized)
    }

    private static func canonicalPath(_ path: String) -> String {
        var value = path
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if value == "/" {
            return ""
        }
        return value
    }

    private static func joinPath(_ base: String, _ suffix: String) -> String {
        let normalizedBase = canonicalPath(base)
        if normalizedBase.isEmpty {
            return suffix.hasPrefix("/") ? suffix : "/\(suffix)"
        }
        if suffix.hasPrefix("/") {
            return normalizedBase + suffix
        }
        return normalizedBase + "/" + suffix
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let normalized = host
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1" {
            return true
        }
        if normalized.hasSuffix(".local") {
            return true
        }
        if isPrivateIPv4Host(normalized) || isPrivateIPv6Host(normalized) {
            return true
        }
        return false
    }

    private static func isPrivateIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }

        switch (octets[0], octets[1]) {
        case (10, _):
            return true
        case (172, 16...31):
            return true
        case (192, 168):
            return true
        case (169, 254):
            return true
        case (127, _):
            return true
        default:
            return false
        }
    }

    private static func isPrivateIPv6Host(_ host: String) -> Bool {
        guard host.contains(":") else { return false }
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if normalized == "::1" { return true }
        if normalized.hasPrefix("fc") || normalized.hasPrefix("fd") {
            return true // Unique local address
        }
        if normalized.hasPrefix("fe80:") {
            return true // Link-local unicast
        }
        return false
    }

    private static func hostMatchesOfficialDomain(_ host: String, domain: String) -> Bool {
        if host == domain {
            return true
        }
        return host.hasSuffix(".\(domain)")
    }

    private static func openAICompatibleURLs(from base: URLComponents) -> (chat: URL, models: URL)? {
        var comps = base
        let path = canonicalPath(comps.path)

        let chatPath: String
        let modelsPath: String

        // Prefer explicit endpoint style from URL:
        // - `/chat/completions` => Chat Completions
        // - `/responses` => Responses API
        // If style is not explicit, default to Responses API.
        if path.hasSuffix("/chat/completions") {
            chatPath = path
            modelsPath = String(path.dropLast("/chat/completions".count)) + "/models"
        } else if path.hasSuffix("/responses") {
            chatPath = path
            modelsPath = String(path.dropLast("/responses".count)) + "/models"
        } else if path.hasSuffix("/models") {
            modelsPath = path
            chatPath = String(path.dropLast("/models".count)) + "/responses"
        } else if path.hasSuffix("/chat") {
            chatPath = path + "/completions"
            modelsPath = String(path.dropLast("/chat".count)) + "/models"
        } else if path.hasSuffix("/v1") || path.hasSuffix("/api/v0") {
            chatPath = path + "/responses"
            modelsPath = path + "/models"
        } else {
            chatPath = joinPath(path, "/v1/responses")
            modelsPath = joinPath(path, "/v1/models")
        }

        comps.path = chatPath
        guard let chatURL = comps.url else { return nil }
        comps.path = modelsPath
        guard let modelsURL = comps.url else { return nil }
        return (chatURL, modelsURL)
    }

    private static func lmStudioURLs(from base: URLComponents) -> (chat: URL, models: URL)? {
        var comps = base
        let path = canonicalPath(comps.path)

        let chatPath: String
        let modelsPath: String

        let nativeBasePath: String
        if path.hasSuffix("/api/v1/chat") {
            nativeBasePath = String(path.dropLast("/chat".count))
        } else if path.hasSuffix("/api/v1/models") {
            nativeBasePath = String(path.dropLast("/models".count))
        } else if path.hasSuffix("/api/v1") {
            nativeBasePath = path
        } else if path.hasSuffix("/v1/chat/completions") {
            let prefix = String(path.dropLast("/v1/chat/completions".count))
            nativeBasePath = joinPath(prefix, "/api/v1")
        } else if path.hasSuffix("/v1/models") {
            let prefix = String(path.dropLast("/v1/models".count))
            nativeBasePath = joinPath(prefix, "/api/v1")
        } else if path.hasSuffix("/v1") {
            let prefix = String(path.dropLast("/v1".count))
            nativeBasePath = joinPath(prefix, "/api/v1")
        } else if path.hasSuffix("/api/v0/chat/completions") {
            let prefix = String(path.dropLast("/api/v0/chat/completions".count))
            nativeBasePath = joinPath(prefix, "/api/v1")
        } else if path.hasSuffix("/api/v0/models") {
            let prefix = String(path.dropLast("/api/v0/models".count))
            nativeBasePath = joinPath(prefix, "/api/v1")
        } else if path.hasSuffix("/api/v0") {
            let prefix = String(path.dropLast("/api/v0".count))
            nativeBasePath = joinPath(prefix, "/api/v1")
        } else {
            nativeBasePath = joinPath(path, "/api/v1")
        }

        chatPath = nativeBasePath + "/chat"
        modelsPath = nativeBasePath + "/models"

        comps.path = chatPath
        guard let chatURL = comps.url else { return nil }
        comps.path = modelsPath
        guard let modelsURL = comps.url else { return nil }
        return (chatURL, modelsURL)
    }

    private static func anthropicURLs(from base: URLComponents) -> (chat: URL, models: URL)? {
        var comps = base
        let path = canonicalPath(comps.path)

        let chatPath: String
        let modelsPath: String

        if path.hasSuffix("/v1/messages") {
            chatPath = path
            modelsPath = String(path.dropLast("/messages".count)) + "/models"
        } else if path.hasSuffix("/v1/models") {
            modelsPath = path
            chatPath = String(path.dropLast("/models".count)) + "/messages"
        } else if path.hasSuffix("/v1") {
            chatPath = path + "/messages"
            modelsPath = path + "/models"
        } else {
            chatPath = joinPath(path, "/v1/messages")
            modelsPath = joinPath(path, "/v1/models")
        }

        comps.path = chatPath
        guard let chatURL = comps.url else { return nil }
        comps.path = modelsPath
        guard let modelsURL = comps.url else { return nil }
        return (chatURL, modelsURL)
    }
}

struct ModelListResponse: Decodable {
    let object: String?
    let data: [ModelInfo]

    private enum CodingKeys: String, CodingKey {
        case object
        case data
        case models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)

        if let standardData = try? container.decode([ModelInfo].self, forKey: .data) {
            data = standardData
            return
        }

        if let lmStudioModels = try? container.decode([LMStudioRESTModelRecord].self, forKey: .models) {
            data = lmStudioModels.compactMap { $0.asModelInfo() }
            return
        }

        data = []
    }
}

private struct LMStudioRESTModelRecord: Decodable {
    let type: String?
    let key: String?
    let id: String?
    let architecture: String?
    let input_modalities: [String]?
    let modalities: [String]?
    let capabilities: LMStudioRESTModelCapabilities?
    let loaded_instances: [LMStudioRESTLoadedInstance]?

    func asModelInfo() -> ModelInfo? {
        let candidates: [String?] = [
            loaded_instances?.first?.identifier,
            loaded_instances?.first?.id,
            key,
            id
        ]
        guard let modelID = candidates
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            return nil
        }

        let capabilityModalities = capabilities?.input_modalities ?? capabilities?.modalities
        let mergedInputModalities = input_modalities ?? capabilityModalities
        let mergedModalities = modalities ?? capabilityModalities

        let visionFlag = capabilities?.supports_image_input ?? capabilities?.supports_vision ?? capabilities?.vision
        let multimodalFlag = capabilities?.multimodal
        let capabilityFlags = ModelCapabilityFlags(
            type: type,
            architecture: architecture,
            input_modalities: mergedInputModalities,
            modalities: mergedModalities,
            vision: capabilities?.vision,
            multimodal: capabilities?.multimodal,
            supports_vision: capabilities?.supports_vision ?? capabilities?.vision,
            supports_image_input: capabilities?.supports_image_input ?? capabilities?.supports_vision ?? capabilities?.vision
        )

        return ModelInfo(
            id: modelID,
            object: "model",
            created: nil,
            owned_by: nil,
            type: type,
            arch: architecture,
            input_modalities: mergedInputModalities,
            modalities: mergedModalities,
            vision: visionFlag,
            multimodal: multimodalFlag,
            supports_vision: capabilities?.supports_vision ?? capabilities?.vision,
            supports_image_input: capabilities?.supports_image_input ?? capabilities?.supports_vision ?? capabilities?.vision,
            capabilities: capabilityFlags,
            details: nil,
            model_info: nil
        )
    }
}

private struct LMStudioRESTModelCapabilities: Decodable {
    let vision: Bool?
    let multimodal: Bool?
    let supports_vision: Bool?
    let supports_image_input: Bool?
    let input_modalities: [String]?
    let modalities: [String]?
}

private struct LMStudioRESTLoadedInstance: Decodable {
    let id: String?
    let identifier: String?
}

struct ModelInfo: Codable {
    let id: String
    let object: String?
    let created: Int?
    let owned_by: String?
    let type: String?
    let arch: String?
    let input_modalities: [String]?
    let modalities: [String]?
    let vision: Bool?
    let multimodal: Bool?
    let supports_vision: Bool?
    let supports_image_input: Bool?
    let capabilities: ModelCapabilityFlags?
    let details: ModelCapabilityFlags?
    let model_info: ModelCapabilityFlags?

    var supportsImageInputHint: Bool? {
        if let explicit = supports_image_input ?? supports_vision ?? vision {
            return explicit
        }
        if let explicit = multimodal {
            return explicit
        }

        let modalityCandidates: [[String]?] = [
            input_modalities,
            modalities,
            capabilities?.input_modalities,
            capabilities?.modalities,
            details?.input_modalities,
            details?.modalities,
            model_info?.input_modalities,
            model_info?.modalities
        ]
        let resolvedModalities = modalityCandidates.compactMap { $0 }.first
        let tokens = normalizedTokens(resolvedModalities)
        if !tokens.isEmpty {
            return tokens.contains("image") || tokens.contains("vision")
        }

        let typeCandidates: [String?] = [
            type,
            arch,
            capabilities?.type,
            details?.type,
            model_info?.type,
            capabilities?.architecture,
            details?.architecture,
            model_info?.architecture
        ]
        let typeTokens = normalizedTokens(typeCandidates.compactMap { $0 })
        if typeTokens.contains("vlm") || typeTokens.contains("vision") || typeTokens.contains("multimodal") {
            return true
        }

        return nil
    }

    private func normalizedTokens(_ values: [String]?) -> Set<String> {
        guard let values else { return [] }
        var out: Set<String> = []
        out.reserveCapacity(values.count * 2)
        for value in values {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty else { continue }
            out.insert(normalized)

            let pieces = normalized
                .replacingOccurrences(of: "-", with: "_")
                .split(separator: "_")
                .map(String.init)
            for piece in pieces where !piece.isEmpty {
                out.insert(piece)
            }
        }
        return out
    }
}

struct ModelCapabilityFlags: Codable {
    let type: String?
    let architecture: String?
    let input_modalities: [String]?
    let modalities: [String]?
    let vision: Bool?
    let multimodal: Bool?
    let supports_vision: Bool?
    let supports_image_input: Bool?
}

struct ChatImageAttachment: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var mimeType: String
    var data: Data

    init(id: UUID = UUID(), mimeType: String, data: Data) {
        self.id = id
        self.mimeType = mimeType
        self.data = data
    }

    var dataURLString: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    static func encodeList(_ attachments: [ChatImageAttachment]) -> Data? {
        guard !attachments.isEmpty else { return nil }
        return try? JSONEncoder().encode(attachments)
    }

    static func decodeList(from data: Data?) -> [ChatImageAttachment] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ChatImageAttachment].self, from: data)) ?? []
    }
}

// MARK: - Network Retry

struct NetworkRetryPolicy: Sendable {
    /// Total number of attempts including the initial try. `nil` means retry forever until cancelled.
    let maxAttempts: Int?
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let backoffFactor: Double
    let jitterRatio: Double

    init(
        maxAttempts: Int? = 6,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        backoffFactor: Double = 1.6,
        jitterRatio: Double = 0.2
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(self.baseDelay, maxDelay)
        self.backoffFactor = max(1.0, backoffFactor)
        self.jitterRatio = max(0, min(1, jitterRatio))
    }

    func shouldContinue(afterAttempt attempt: Int) -> Bool {
        guard let maxAttempts else { return true }
        return attempt < maxAttempts
    }

    /// `retryCount` is 1 for the first retry after the initial failure.
    func delay(forRetryCount retryCount: Int) -> TimeInterval {
        guard retryCount > 0 else { return 0 }
        let exponent = Double(max(0, retryCount - 1))
        let raw = baseDelay * pow(backoffFactor, exponent)
        let clamped = min(maxDelay, max(0, raw))
        guard jitterRatio > 0, clamped > 0 else { return clamped }
        let delta = clamped * jitterRatio
        return Double.random(in: max(0, clamped - delta)...(clamped + delta))
    }
}

struct HTTPStatusError: LocalizedError, Sendable {
    let statusCode: Int
    let bodyPreview: String?

    var errorDescription: String? {
        if let bodyPreview, !bodyPreview.isEmpty {
            return "HTTP \(statusCode): \(bodyPreview)"
        }
        return "HTTP \(statusCode)"
    }
}

enum NetworkRetryability {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    static func shouldRetry(_ error: Error) -> Bool {
        if isCancellation(error) { return false }

        if let status = error as? HTTPStatusError {
            return shouldRetry(statusCode: status.statusCode)
        }

        if let url = error as? URLError {
            return shouldRetry(urlCode: url.code)
        }

        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return shouldRetry(urlCode: URLError.Code(rawValue: ns.code))
        }

        return false
    }

    static func shouldRetry(statusCode: Int) -> Bool {
        switch statusCode {
        case 408, 425, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    private static func shouldRetry(urlCode: URLError.Code) -> Bool {
        switch urlCode {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}

enum NetworkRetry {
    static func sleep(seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        do {
            try await Task.sleep(for: .seconds(seconds))
        } catch {
            // Cancellation or sleep failure should stop the retry loop naturally.
        }
    }

    static func run<T>(
        policy: NetworkRetryPolicy,
        shouldRetry: @escaping @Sendable (Error) -> Bool = NetworkRetryability.shouldRetry(_:),
        onRetry: (@Sendable (_ nextAttempt: Int, _ delay: TimeInterval, _ error: Error) async -> Void)? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            attempt += 1
            do {
                try Task.checkCancellation()
                return try await operation()
            } catch {
                if NetworkRetryability.isCancellation(error) { throw error }
                guard shouldRetry(error) else { throw error }
                guard policy.shouldContinue(afterAttempt: attempt) else { throw error }

                let retryCount = attempt
                let delay = policy.delay(forRetryCount: retryCount)
                await onRetry?(attempt + 1, delay, error)
                await sleep(seconds: delay)
                continue
            }
        }
    }
}
