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

        if let preferredStyle,
           let preferred = candidates.first(where: { $0.style == preferredStyle }) {
            return preferred
        }
        return candidates.first
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
        case .gemini:
            appendGeminiCandidate(base: base, to: &list)
        case .deepSeek:
            appendChatCompletionsCandidate(provider: .deepSeek, base: base, to: &list)
        case .xAI:
            appendChatCompletionsCandidate(provider: .xAI, base: base, to: &list)
        case .openRouter:
            appendChatCompletionsCandidate(provider: .openRouter, base: base, to: &list)
        case .llamaCpp:
            appendOpenAICompatibleCandidate(provider: .llamaCpp, base: base, to: &list)
        case .openAI:
            appendOpenAICompatibleCandidate(provider: .openAI, base: base, to: &list)
        case .openAICompatible, .unknown:
            appendOpenAICompatibleCandidate(provider: .openAICompatible, base: base, to: &list)
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

    private static func appendGeminiCandidate(
        base: URLComponents,
        to list: inout [ChatAPIEndpointCandidate]
    ) {
        guard let urls = ChatEndpointProviderURLFactory.geminiOpenAICompatibleURLs(from: base) else { return }
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

    private static func appendChatCompletionsCandidate(
        provider: ChatProvider,
        base: URLComponents,
        to list: inout [ChatAPIEndpointCandidate]
    ) {
        guard let urls = ChatEndpointProviderURLFactory.chatCompletionsCompatibleURLs(from: base) else { return }
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

    private static func appendOpenAICompatibleCandidate(
        provider: ChatProvider,
        base: URLComponents,
        to list: inout [ChatAPIEndpointCandidate]
    ) {
        guard let urls = ChatEndpointProviderURLFactory.openAICompatibleURLs(from: base) else { return }
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
