//
//  ChatEndpointProviderURLFactory.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

enum ChatEndpointProviderURLFactory {
    static func openAICompatibleURLs(from base: URLComponents) -> (chat: URL, models: URL)? {
        let path = ChatEndpointBaseURL.canonicalPath(base.path)

        let chatPath: String
        let modelsPath: String

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
            chatPath = ChatEndpointBaseURL.joinPath(path, "/v1/responses")
            modelsPath = ChatEndpointBaseURL.joinPath(path, "/v1/models")
        }

        return urls(from: base, chatPath: chatPath, modelsPath: modelsPath)
    }

    static func chatCompletionsCompatibleURLs(from base: URLComponents) -> (chat: URL, models: URL)? {
        let path = ChatEndpointBaseURL.canonicalPath(base.path)

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
            chatPath = ChatEndpointBaseURL.joinPath(path, "/v1/chat/completions")
            modelsPath = ChatEndpointBaseURL.joinPath(path, "/v1/models")
        }

        return urls(from: base, chatPath: chatPath, modelsPath: modelsPath)
    }

    static func geminiOpenAICompatibleURLs(from base: URLComponents) -> (chat: URL, models: URL)? {
        let path = ChatEndpointBaseURL.canonicalPath(base.path)

        func geminiCompatibilityBase(from candidate: String) -> String {
            if candidate.hasSuffix("/openai") {
                return candidate
            }
            if candidate.hasSuffix("/v1beta") || candidate.hasSuffix("/v1") {
                return candidate + "/openai"
            }
            return ChatEndpointBaseURL.joinPath(candidate, "/v1beta/openai")
        }

        let compatibilityBase: String
        if path.hasSuffix("/chat/completions") {
            compatibilityBase = String(path.dropLast("/chat/completions".count))
        } else if path.hasSuffix("/models") {
            compatibilityBase = geminiCompatibilityBase(from: String(path.dropLast("/models".count)))
        } else {
            compatibilityBase = geminiCompatibilityBase(from: path)
        }

        return urls(
            from: base,
            chatPath: compatibilityBase + "/chat/completions",
            modelsPath: compatibilityBase + "/models"
        )
    }

    static func lmStudioURLs(from base: URLComponents) -> (chat: URL, models: URL)? {
        let path = ChatEndpointBaseURL.canonicalPath(base.path)

        let nativeBasePath: String
        if path.hasSuffix("/api/v1/chat") {
            nativeBasePath = String(path.dropLast("/chat".count))
        } else if path.hasSuffix("/api/v1/models") {
            nativeBasePath = String(path.dropLast("/models".count))
        } else if path.hasSuffix("/api/v1") {
            nativeBasePath = path
        } else if path.hasSuffix("/v1/chat/completions") {
            let prefix = String(path.dropLast("/v1/chat/completions".count))
            nativeBasePath = ChatEndpointBaseURL.joinPath(prefix, "/api/v1")
        } else if path.hasSuffix("/v1/models") {
            let prefix = String(path.dropLast("/v1/models".count))
            nativeBasePath = ChatEndpointBaseURL.joinPath(prefix, "/api/v1")
        } else if path.hasSuffix("/v1") {
            let prefix = String(path.dropLast("/v1".count))
            nativeBasePath = ChatEndpointBaseURL.joinPath(prefix, "/api/v1")
        } else if path.hasSuffix("/api/v0/chat/completions") {
            let prefix = String(path.dropLast("/api/v0/chat/completions".count))
            nativeBasePath = ChatEndpointBaseURL.joinPath(prefix, "/api/v1")
        } else if path.hasSuffix("/api/v0/models") {
            let prefix = String(path.dropLast("/api/v0/models".count))
            nativeBasePath = ChatEndpointBaseURL.joinPath(prefix, "/api/v1")
        } else if path.hasSuffix("/api/v0") {
            let prefix = String(path.dropLast("/api/v0".count))
            nativeBasePath = ChatEndpointBaseURL.joinPath(prefix, "/api/v1")
        } else {
            nativeBasePath = ChatEndpointBaseURL.joinPath(path, "/api/v1")
        }

        return urls(
            from: base,
            chatPath: nativeBasePath + "/chat",
            modelsPath: nativeBasePath + "/models"
        )
    }

    static func anthropicURLs(from base: URLComponents) -> (chat: URL, models: URL)? {
        let path = ChatEndpointBaseURL.canonicalPath(base.path)

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
            chatPath = ChatEndpointBaseURL.joinPath(path, "/v1/messages")
            modelsPath = ChatEndpointBaseURL.joinPath(path, "/v1/models")
        }

        return urls(from: base, chatPath: chatPath, modelsPath: modelsPath)
    }

    private static func urls(
        from base: URLComponents,
        chatPath: String,
        modelsPath: String
    ) -> (chat: URL, models: URL)? {
        var comps = base
        comps.path = chatPath
        guard let chatURL = comps.url else { return nil }
        comps.path = modelsPath
        guard let modelsURL = comps.url else { return nil }
        return (chatURL, modelsURL)
    }
}
