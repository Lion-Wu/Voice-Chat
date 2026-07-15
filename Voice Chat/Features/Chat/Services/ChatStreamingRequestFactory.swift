//
//  ChatStreamingRequestFactory.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

protocol ChatStreamingRequestBuilding: Sendable {
    func makeStreamingRequest(
        endpoint: ChatAPIEndpointCandidate,
        requestBodyData: Data,
        apiKey: String
    ) -> URLRequest
}

struct ChatStreamingRequestFactory: ChatStreamingRequestBuilding, Sendable {
    func makeStreamingRequest(
        endpoint: ChatAPIEndpointCandidate,
        requestBodyData: Data,
        apiKey: String
    ) -> URLRequest {
        var request = URLRequest(url: endpoint.chatURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 3900
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("keep-alive", forHTTPHeaderField: "Connection")
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")
        applyAuthHeaders(to: &request, endpoint: endpoint, rawAPIKey: apiKey)
        request.httpBody = requestBodyData
        return request
    }

    private func normalizedAPIKeyForXAPIKeyHeader(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func applyAuthHeaders(to request: inout URLRequest, endpoint: ChatAPIEndpointCandidate, rawAPIKey: String) {
        let rawKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch endpoint.style {
        case .anthropicMessages:
            if usesBearerAuthForAnthropicMessages(endpoint.chatURL) {
                if !rawKey.isEmpty {
                    let headerValue = rawKey.lowercased().hasPrefix("bearer ") ? rawKey : "Bearer \(rawKey)"
                    request.setValue(headerValue, forHTTPHeaderField: "Authorization")
                }
            } else {
                let keyForHeader = normalizedAPIKeyForXAPIKeyHeader(rawKey)
                if !keyForHeader.isEmpty {
                    request.setValue(keyForHeader, forHTTPHeaderField: "x-api-key")
                }
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }

        case .openAIResponses, .openAIChatCompletions, .lmStudioRESTV1:
            if !rawKey.isEmpty {
                if usesAzureOpenAIAPIKeyAuth(endpoint.chatURL, rawAPIKey: rawKey) {
                    request.setValue(normalizedAPIKeyForXAPIKeyHeader(rawKey), forHTTPHeaderField: "api-key")
                } else {
                    let headerValue = rawKey.lowercased().hasPrefix("bearer ") ? rawKey : "Bearer \(rawKey)"
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
