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
    case gemini = "gemini"
    case deepSeek = "deepseek"
    case xAI = "xai"
    case openRouter = "openrouter"
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
        case .gemini:
            return NSLocalizedString("Gemini", comment: "Provider display name")
        case .deepSeek:
            return NSLocalizedString("DeepSeek", comment: "Provider display name")
        case .xAI:
            return NSLocalizedString("xAI", comment: "Provider display name")
        case .openRouter:
            return NSLocalizedString("OpenRouter", comment: "Provider display name")
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
    case gemini
    case deepSeek
    case xAI
    case openRouter
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
        case .gemini:
            return .gemini
        case .deepSeek:
            return .deepSeek
        case .xAI:
            return .xAI
        case .openRouter:
            return .openRouter
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
        case .openAI, .gemini, .deepSeek, .xAI, .openRouter, .llamaCpp, .openAICompatible:
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
        if hostMatchesOfficialDomain(host, domain: "googleapis.com") {
            return .gemini
        }
        if hostMatchesOfficialDomain(host, domain: "deepseek.com") {
            return .deepSeek
        }
        if hostMatchesOfficialDomain(host, domain: "x.ai") {
            return .xAI
        }
        if hostMatchesOfficialDomain(host, domain: "openrouter.ai") {
            return .openRouter
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
        let looksGemini = host.contains("googleapis.com") || path.contains("/v1beta/openai")
        let looksDeepSeek = host.contains("deepseek.com")
        let looksXAI = host.contains("x.ai")
        let looksOpenRouter = host.contains("openrouter.ai")
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
        if looksGemini {
            appendHeuristic(.gemini)
        }
        if looksDeepSeek {
            appendHeuristic(.deepSeek)
        }
        if looksXAI {
            appendHeuristic(.xAI)
        }
        if looksOpenRouter {
            appendHeuristic(.openRouter)
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
                append(.gemini)
                append(.deepSeek)
                append(.xAI)
                append(.openRouter)
            }
        }

        append(.lmStudio)
        append(.llamaCpp)
        append(.openAICompatible)
        append(.openAI)
        append(.anthropic)
        append(.gemini)
        append(.deepSeek)
        append(.xAI)
        append(.openRouter)

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

        case .gemini:
            if let urls = geminiOpenAICompatibleURLs(from: base) {
                appendUnique(
                    ChatAPIEndpointCandidate(
                        provider: .gemini,
                        style: .openAIChatCompletions,
                        chatURL: urls.chat,
                        modelsURL: urls.models
                    ),
                    to: &list
                )
            }

        case .deepSeek:
            if let urls = chatCompletionsCompatibleURLs(from: base) {
                appendUnique(
                    ChatAPIEndpointCandidate(
                        provider: .deepSeek,
                        style: .openAIChatCompletions,
                        chatURL: urls.chat,
                        modelsURL: urls.models
                    ),
                    to: &list
                )
            }

        case .xAI:
            if let urls = chatCompletionsCompatibleURLs(from: base) {
                appendUnique(
                    ChatAPIEndpointCandidate(
                        provider: .xAI,
                        style: .openAIChatCompletions,
                        chatURL: urls.chat,
                        modelsURL: urls.models
                    ),
                    to: &list
                )
            }

        case .openRouter:
            if let urls = chatCompletionsCompatibleURLs(from: base) {
                appendUnique(
                    ChatAPIEndpointCandidate(
                        provider: .openRouter,
                        style: .openAIChatCompletions,
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

    private static func chatCompletionsCompatibleURLs(from base: URLComponents) -> (chat: URL, models: URL)? {
        var comps = base
        let path = canonicalPath(comps.path)

        let chatPath: String
        let modelsPath: String

        if path.hasSuffix("/chat/completions") {
            chatPath = path
            modelsPath = String(path.dropLast("/chat/completions".count)) + "/models"
        } else if path.hasSuffix("/models") {
            modelsPath = path
            chatPath = String(path.dropLast("/models".count)) + "/chat/completions"
        } else if path.hasSuffix("/chat") {
            chatPath = path + "/completions"
            modelsPath = String(path.dropLast("/chat".count)) + "/models"
        } else if path.hasSuffix("/v1") {
            chatPath = path + "/chat/completions"
            modelsPath = path + "/models"
        } else {
            chatPath = joinPath(path, "/v1/chat/completions")
            modelsPath = joinPath(path, "/v1/models")
        }

        comps.path = chatPath
        guard let chatURL = comps.url else { return nil }
        comps.path = modelsPath
        guard let modelsURL = comps.url else { return nil }
        return (chatURL, modelsURL)
    }

    private static func geminiOpenAICompatibleURLs(from base: URLComponents) -> (chat: URL, models: URL)? {
        var comps = base
        let path = canonicalPath(comps.path)

        func geminiCompatibilityBase(from candidate: String) -> String {
            if candidate.hasSuffix("/openai") {
                return candidate
            }
            if candidate.hasSuffix("/v1beta") || candidate.hasSuffix("/v1") {
                return candidate + "/openai"
            }
            return joinPath(candidate, "/v1beta/openai")
        }

        let compatibilityBase: String
        if path.hasSuffix("/chat/completions") {
            compatibilityBase = String(path.dropLast("/chat/completions".count))
        } else if path.hasSuffix("/models") {
            compatibilityBase = geminiCompatibilityBase(from: String(path.dropLast("/models".count)))
        } else {
            compatibilityBase = geminiCompatibilityBase(from: path)
        }

        comps.path = compatibilityBase + "/chat/completions"
        guard let chatURL = comps.url else { return nil }
        comps.path = compatibilityBase + "/models"
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
