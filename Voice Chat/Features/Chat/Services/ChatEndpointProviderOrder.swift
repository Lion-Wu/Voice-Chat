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
            append(.lmStudio)
            append(.llamaCpp)
            append(.openAICompatible)
            if !context.isLocal {
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

    private static func heuristicProviders(for context: ChatEndpointProviderOrderContext) -> [ChatProvider] {
        var providers: [ChatProvider] = []

        func append(_ provider: ChatProvider) {
            guard !providers.contains(provider) else { return }
            providers.append(provider)
        }

        if context.host.contains("anthropic.com") || context.path.hasSuffix("/v1/messages") {
            append(.anthropic)
        }
        if context.host.contains("googleapis.com") || context.path.contains("/v1beta/openai") {
            append(.gemini)
        }
        if context.host.contains("deepseek.com") {
            append(.deepSeek)
        }
        if context.host.contains("x.ai") {
            append(.xAI)
        }
        if context.host.contains("openrouter.ai") {
            append(.openRouter)
        }
        if context.host.contains("lmstudio") || context.path.contains("/api/v1") || context.path.contains("/api/v0") || (context.isLocal && context.port == 1234) {
            append(.lmStudio)
        }
        if context.host.contains("openai.com") {
            append(.openAI)
        }
        if context.host.contains("llama") || context.path.contains("llama.cpp") || (context.isLocal && (context.port == 8080 || context.port == 8081)) {
            append(.llamaCpp)
        }

        return providers
    }
}
