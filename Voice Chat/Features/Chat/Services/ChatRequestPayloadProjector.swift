//
//  ChatRequestPayloadProjector.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatRequestSourceMessage: Equatable, Sendable {
    let content: String
    let isUser: Bool
    let imageAttachments: [ChatImageAttachment]
    let providerResponseID: String?
    let createdAt: Date

    init(
        content: String,
        isUser: Bool,
        imageAttachments: [ChatImageAttachment] = [],
        providerResponseID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.content = content
        self.isUser = isUser
        self.imageAttachments = imageAttachments
        self.providerResponseID = providerResponseID
        self.createdAt = createdAt
    }
}

protocol ChatRequestPayloadProjecting: Sendable {
    func transformedMessagesForRequest(
        messages: [ChatRequestSourceMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) -> [[String: Any]]
}

struct ChatRequestPayloadProjector: ChatRequestPayloadProjecting, Sendable {
    func transformedMessagesForRequest(
        messages: [ChatRequestSourceMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) -> [[String: Any]] {
        var payload: [[String: Any]] = []
        if let prompt = developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            payload.append([
                "role": "developer",
                "content": prompt
            ])
        }

        for message in messages where !message.content.hasPrefix("!error:") {
            let role = message.isUser ? "user" : "assistant"
            let textContent = message.content
            let imageAttachments = includeImagesInUserContent ? message.imageAttachments : []

            if message.isUser, !imageAttachments.isEmpty {
                var parts: [[String: Any]] = []
                if !textContent.isEmpty {
                    parts.append([
                        "type": "text",
                        "text": textContent
                    ])
                }

                for attachment in imageAttachments where !attachment.data.isEmpty {
                    parts.append([
                        "type": "image_url",
                        "image_url": [
                            "url": attachment.dataURLString
                        ]
                    ])
                }

                if !parts.isEmpty {
                    payload.append([
                        "role": role,
                        "content": parts
                    ])
                    continue
                }
            }

            payload.append([
                "role": role,
                "content": textContent
            ])
        }
        return payload
    }
}
