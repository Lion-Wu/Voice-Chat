//
//  ChatEndpointCandidateFactory.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

enum ChatEndpointCandidateFactory {
    static func candidate(
        for provider: ChatProvider,
        base: URLComponents,
        preferredStyle: ChatRequestStyle? = nil
    ) -> ChatAPIEndpointCandidate? {
        var candidates: [ChatAPIEndpointCandidate] = []
        appendCandidates(for: provider, base: base, to: &candidates)
        guard !candidates.isEmpty else { return nil }

        let effectivePreferredStyle = preferredStyle
            ?? explicitStyleHint(from: base)
            ?? ChatEndpointOfficialProviderDetector.preferredRequestStyle(for: base)
        if let effectivePreferredStyle,
           let preferred = candidates.first(where: { $0.style == effectivePreferredStyle }) {
            return preferred
        }
        return candidates.first
    }

    static func explicitStyleHint(from base: URLComponents) -> ChatRequestStyle? {
        let path = ChatEndpointBaseURL.canonicalPath(base.path).lowercased()
        if path.hasSuffix("/chat/completions") {
            return .openAIChatCompletions
        }
        if path.hasSuffix("/responses") {
            return .openAIResponses
        }
        if path.hasSuffix("/api/v1/chat") {
            return .lmStudioRESTV1
        }
        return nil
    }

    static func appendCandidates(
        for provider: ChatProvider,
        base: URLComponents,
        to list: inout [ChatAPIEndpointCandidate]
    ) {
        switch provider {
        case .lmStudio:
            appendLMStudioCandidates(base: base, to: &list)
        case .anthropic:
            appendAnthropicCandidate(base: base, to: &list)
        case .openAI:
            appendOpenAICompatibleCandidates(provider: .openAI, base: base, to: &list)
        case .unknown:
            appendOpenAICompatibleCandidates(provider: .unknown, base: base, to: &list)
        }
    }

    private static func appendLMStudioCandidates(
        base: URLComponents,
        to list: inout [ChatAPIEndpointCandidate]
    ) {
        if let urls = ChatEndpointProviderURLFactory.lmStudioURLs(from: base) {
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
        if let urls = ChatEndpointProviderURLFactory.openAICompatibleURLs(from: base) {
            appendUnique(
                ChatAPIEndpointCandidate(
                    provider: .lmStudio,
                    style: .openAIResponses,
                    chatURL: urls.chat,
                    modelsURL: urls.models
                ),
                to: &list
            )
        }
        if let urls = ChatEndpointProviderURLFactory.chatCompletionsCompatibleURLs(from: base) {
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
    }

    private static func appendAnthropicCandidate(
        base: URLComponents,
        to list: inout [ChatAPIEndpointCandidate]
    ) {
        guard let urls = ChatEndpointProviderURLFactory.anthropicURLs(from: base) else { return }
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

    private static func appendOpenAICompatibleCandidates(
        provider: ChatProvider,
        base: URLComponents,
        to list: inout [ChatAPIEndpointCandidate]
    ) {
        if let urls = ChatEndpointProviderURLFactory.openAICompatibleURLs(from: base) {
            appendUnique(
                ChatAPIEndpointCandidate(
                    provider: provider,
                    style: .openAIResponses,
                    chatURL: urls.chat,
                    modelsURL: urls.models
                ),
                to: &list
            )
        }
        if let urls = ChatEndpointProviderURLFactory.chatCompletionsCompatibleURLs(from: base) {
            appendUnique(
                ChatAPIEndpointCandidate(
                    provider: provider,
                    style: .openAIChatCompletions,
                    chatURL: urls.chat,
                    modelsURL: urls.models
                ),
                to: &list
            )
        }
    }

    private static func appendUnique(
        _ candidate: ChatAPIEndpointCandidate,
        to list: inout [ChatAPIEndpointCandidate]
    ) {
        if list.contains(where: { $0.style == candidate.style && $0.chatURL == candidate.chatURL }) {
            return
        }
        list.append(candidate)
    }
}
