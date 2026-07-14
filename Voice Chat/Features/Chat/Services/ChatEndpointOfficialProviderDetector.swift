//
//  ChatEndpointOfficialProviderDetector.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

enum ChatEndpointOfficialProviderDetector {
    private enum OpenAICompatibleCapability {
        case responses
        case chatCompletions
    }

    static func providerHint(for base: String) -> ChatProvider? {
        guard let comps = ChatEndpointBaseURL.normalizedComponents(from: base) else { return nil }
        let host = (comps.host ?? "").lowercased()

        if ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "openai.com") {
            return .openAI
        }
        if ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "anthropic.com") {
            return .anthropic
        }
        if openAICompatibleCapability(for: host) != nil {
            return .openAI
        }
        return nil
    }

    static func preferredRequestStyle(for base: URLComponents) -> ChatRequestStyle? {
        let host = (base.host ?? "").lowercased()
        if ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "anthropic.com") {
            return .anthropicMessages
        }
        switch openAICompatibleCapability(for: host) {
        case .responses:
            return .openAIResponses
        case .chatCompletions:
            return .openAIChatCompletions
        case nil:
            return nil
        }
    }

    static func isChatCompletionsOnlyOpenAICompatibleHost(_ host: String) -> Bool {
        openAICompatibleCapability(for: host.lowercased()) == .chatCompletions
    }

    static func isKnownOpenAICompatibleHost(_ host: String) -> Bool {
        openAICompatibleCapability(for: host.lowercased()) != nil
    }

    private static func openAICompatibleCapability(for host: String) -> OpenAICompatibleCapability? {
        let normalized = host.lowercased()
        if matchesAny(
            normalized,
            domains: [
                "openai.com",
                "openrouter.ai",
                "x.ai",
                "perplexity.ai",
                "openai.azure.com"
            ]
        ) {
            return .responses
        }
        if matchesAny(
            normalized,
            domains: [
                "googleapis.com",
                "deepseek.com",
                "mistral.ai",
                "together.ai"
            ]
        ) {
            return .chatCompletions
        }
        return nil
    }

    private static func matchesAny(_ host: String, domains: [String]) -> Bool {
        domains.contains {
            ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: $0)
        }
    }
}
