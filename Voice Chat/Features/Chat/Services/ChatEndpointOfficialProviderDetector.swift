//
//  ChatEndpointOfficialProviderDetector.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

enum ChatEndpointOfficialProviderDetector {
    static func providerHint(for base: String) -> ChatProvider? {
        guard let comps = ChatEndpointBaseURL.normalizedComponents(from: base) else { return nil }
        let host = (comps.host ?? "").lowercased()

        if ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "openai.com") {
            return .openAI
        }
        if ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "anthropic.com") {
            return .anthropic
        }
        if ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "googleapis.com") {
            return .gemini
        }
        if ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "deepseek.com") {
            return .deepSeek
        }
        if ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "x.ai") {
            return .xAI
        }
        if ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "openrouter.ai") {
            return .openRouter
        }
        return nil
    }
}
