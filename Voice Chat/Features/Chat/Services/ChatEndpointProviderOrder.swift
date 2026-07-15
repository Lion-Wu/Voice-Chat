//
//  ChatEndpointProviderOrder.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation

struct ChatEndpointProviderOrderContext: Equatable, Sendable {
    let path: String
    let host: String
    let port: Int?
    let isLocal: Bool
}

enum ChatEndpointProviderOrder {
    static func providers(
        for context: ChatEndpointProviderOrderContext,
        preferred: ChatProvider?
    ) -> [ChatProvider] {
        var order: [ChatProvider] = []

        func append(_ provider: ChatProvider) {
            guard !order.contains(provider) else { return }
            order.append(provider)
        }

        let heuristicOrder = heuristicProviders(for: context)

        if !heuristicOrder.isEmpty {
            heuristicOrder.forEach(append)
            if let preferred, preferred != .unknown, !heuristicOrder.contains(preferred) {
                append(preferred)
            }
        } else {
            if let preferred, preferred != .unknown {
                append(preferred)
            }
            append(.unknown)
            append(.openAI)
        }

        append(.unknown)
        if context.isLocal || preferred == .lmStudio || heuristicOrder.contains(.lmStudio) {
            append(.lmStudio)
        }
        append(.openAI)
        if preferred == .anthropic || heuristicOrder.contains(.anthropic) {
            append(.anthropic)
        }

        return order
    }

    private static func heuristicProviders(for context: ChatEndpointProviderOrderContext) -> [ChatProvider] {
        var providers: [ChatProvider] = []

        func append(_ provider: ChatProvider) {
            guard !providers.contains(provider) else { return }
            providers.append(provider)
        }

        if ChatEndpointBaseURL.hostMatchesOfficialDomain(context.host, domain: "anthropic.com") {
            append(.anthropic)
        }
        if ChatEndpointOfficialProviderDetector.isKnownOpenAICompatibleHost(context.host) ||
            context.path.contains("/v1beta/openai") {
            append(.openAI)
        }
        if context.host.contains("lmstudio") ||
            (context.isLocal && (context.port == 1234 || context.path.contains("/api/v1") || context.path.contains("/api/v0"))) {
            append(.lmStudio)
        }

        return providers
    }
}
