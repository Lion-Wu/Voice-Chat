//
//  ChatEndpointResolving.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

protocol ChatEndpointResolving: Sendable {
    func endpointCandidates(for base: String, preferredProvider: ChatProvider?) -> [ChatAPIEndpointCandidate]
    func streamingCandidates(
        for base: String,
        providerHint: ChatProvider?,
        styleHint: ChatRequestStyle?
    ) -> [ChatAPIEndpointCandidate]
}

struct DefaultChatEndpointResolver: ChatEndpointResolving {
    func endpointCandidates(for base: String, preferredProvider: ChatProvider?) -> [ChatAPIEndpointCandidate] {
        ChatAPIEndpointResolver.endpointCandidates(for: base, preferredProvider: preferredProvider)
    }

    func streamingCandidates(
        for base: String,
        providerHint: ChatProvider?,
        styleHint: ChatRequestStyle?
    ) -> [ChatAPIEndpointCandidate] {
        var candidates = endpointCandidates(for: base, preferredProvider: providerHint)

        if let providerHint, providerHint != .unknown {
            let providerMatched = candidates.filter { $0.provider == providerHint }
            if !providerMatched.isEmpty {
                candidates = providerMatched
            }
        }

        if let styleHint {
            let styleMatched = candidates.filter { $0.style == styleHint }
            if !styleMatched.isEmpty {
                candidates = styleMatched
            }
        }

        return prioritized(candidates, preferredStyle: styleHint ?? defaultStyleHint(for: base))
    }

    private func prioritized(
        _ candidates: [ChatAPIEndpointCandidate],
        preferredStyle: ChatRequestStyle?
    ) -> [ChatAPIEndpointCandidate] {
        guard let preferredStyle else { return candidates }
        return candidates.enumerated().sorted { lhs, rhs in
            let lhsPreferred = lhs.element.style == preferredStyle
            let rhsPreferred = rhs.element.style == preferredStyle
            if lhsPreferred != rhsPreferred {
                return lhsPreferred && !rhsPreferred
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func defaultStyleHint(for base: String) -> ChatRequestStyle? {
        guard let comps = ChatEndpointBaseURL.normalizedComponents(from: base) else { return nil }
        return ChatEndpointCandidateFactory.explicitStyleHint(from: comps)
            ?? ChatEndpointOfficialProviderDetector.preferredRequestStyle(for: comps)
    }
}

enum ChatAPIEndpointResolver {
    static func officialProviderHint(for base: String) -> ChatProvider? {
        ChatEndpointOfficialProviderDetector.providerHint(for: base)
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
        guard let comps = ChatEndpointBaseURL.normalizedComponents(from: base) else { return nil }
        return ChatEndpointCandidateFactory.candidate(
            for: provider,
            base: comps,
            preferredStyle: preferredStyle
        )
    }

    static func autoDetectionCandidates(
        for base: String,
        preferredProvider: ChatProvider? = nil
    ) -> [ChatAPIEndpointCandidate] {
        guard let comps = ChatEndpointBaseURL.normalizedComponents(from: base) else { return [] }

        var candidates = endpointCandidates(for: base, preferredProvider: preferredProvider)
        candidates = uniqueCandidates(candidates)

        if candidates.isEmpty {
            return fallbackCandidates(for: base, preferredProvider: preferredProvider)
        }

        let preferredStyle = ChatEndpointCandidateFactory.explicitStyleHint(from: comps)
            ?? ChatEndpointOfficialProviderDetector.preferredRequestStyle(for: comps)
        return prioritized(candidates, preferredStyle: preferredStyle)
    }

    static func normalizedAPIBaseKey(_ base: String) -> String? {
        ChatEndpointBaseURL.normalizedAPIBaseKey(base)
    }

    static func endpointCandidates(for base: String, preferredProvider: ChatProvider? = nil) -> [ChatAPIEndpointCandidate] {
        guard let comps = ChatEndpointBaseURL.normalizedComponents(from: base) else { return [] }
        let path = ChatEndpointBaseURL.canonicalPath(comps.path).lowercased()
        let host = (comps.host ?? "").lowercased()
        let port = comps.port

        let order = providerOrder(path: path, host: host, port: port, preferred: preferredProvider)

        var candidates: [ChatAPIEndpointCandidate] = []
        candidates.reserveCapacity(order.count + 2)

        for provider in order {
            ChatEndpointCandidateFactory.appendCandidates(for: provider, base: comps, to: &candidates)
        }
        return candidates
    }

    private static func fallbackCandidates(
        for base: String,
        preferredProvider: ChatProvider?
    ) -> [ChatAPIEndpointCandidate] {
        var fallback = endpointCandidates(for: base, preferredProvider: preferredProvider)
        if let preferredProvider {
            let preferredOnly = fallback.filter { $0.provider == preferredProvider }
            if !preferredOnly.isEmpty {
                fallback = preferredOnly
            }
        }
        return fallback
    }

    private static func prioritized(
        _ candidates: [ChatAPIEndpointCandidate],
        preferredStyle: ChatRequestStyle?
    ) -> [ChatAPIEndpointCandidate] {
        guard let preferredStyle else { return candidates }
        return candidates.enumerated().sorted { lhs, rhs in
            let lhsPreferred = lhs.element.style == preferredStyle
            let rhsPreferred = rhs.element.style == preferredStyle
            if lhsPreferred != rhsPreferred {
                return lhsPreferred && !rhsPreferred
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func uniqueCandidates(_ candidates: [ChatAPIEndpointCandidate]) -> [ChatAPIEndpointCandidate] {
        var unique: [ChatAPIEndpointCandidate] = []
        unique.reserveCapacity(candidates.count)
        for candidate in candidates {
            appendUnique(candidate, to: &unique)
        }
        return unique
    }

    private static func providerOrder(path: String, host: String, port: Int?, preferred: ChatProvider?) -> [ChatProvider] {
        ChatEndpointProviderOrder.providers(
            for: ChatEndpointProviderOrderContext(
                path: path,
                host: host,
                port: port,
                isLocal: ChatEndpointBaseURL.isLocalHost(host)
            ),
            preferred: preferred
        )
    }

    private static func appendUnique(
        _ candidate: ChatAPIEndpointCandidate?,
        to list: inout [ChatAPIEndpointCandidate]
    ) {
        guard let candidate else { return }
        if list.contains(where: { $0.style == candidate.style && $0.chatURL == candidate.chatURL }) {
            return
        }
        list.append(candidate)
    }
}
