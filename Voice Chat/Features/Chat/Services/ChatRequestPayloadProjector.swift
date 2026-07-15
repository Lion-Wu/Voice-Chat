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
    let requestContextFingerprint: String?
    let requestContentSnapshot: String?
    let assistantSegments: [ChatAssistantSegment]
    let openAIResponsesConversationItems: [JSONValue]
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let createdAt: Date

    init(
        content: String,
        isUser: Bool,
        imageAttachments: [ChatImageAttachment] = [],
        providerResponseID: String? = nil,
        requestContextFingerprint: String? = nil,
        requestContentSnapshot: String? = nil,
        assistantSegments: [ChatAssistantSegment] = [],
        openAIResponsesConversationItems: [JSONValue] = [],
        toolActivityPlacements: [ChatToolActivityPlacement] = [],
        createdAt: Date = Date()
    ) {
        self.content = content
        self.isUser = isUser
        self.imageAttachments = imageAttachments
        self.providerResponseID = providerResponseID
        self.requestContextFingerprint = requestContextFingerprint
        self.requestContentSnapshot = requestContentSnapshot
        self.assistantSegments = assistantSegments
        self.openAIResponsesConversationItems = openAIResponsesConversationItems
        self.toolActivityPlacements = toolActivityPlacements
        self.createdAt = createdAt
    }
}

protocol ChatRequestPayloadProjecting: Sendable {
    func transformedMessagesForRequest(
        messages: [ChatRequestSourceMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool,
        requestStyle: ChatRequestStyle?
    ) -> [[String: Any]]
}

struct ChatRequestPayloadProjector: ChatRequestPayloadProjecting, Sendable {
    func transformedMessagesForRequest(
        messages: [ChatRequestSourceMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool,
        requestStyle: ChatRequestStyle? = nil
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
            if requestStyle == .openAIResponses,
               !message.isUser,
               !message.openAIResponsesConversationItems.isEmpty {
                payload.append(contentsOf: message.openAIResponsesConversationItems.compactMap { value in
                    value.jsonObject as? [String: Any]
                })
                continue
            }

            let role = message.isUser ? "user" : "assistant"
            let textContent = Self.requestContent(for: message)
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

            var item: [String: Any] = [
                "role": role,
                "content": textContent
            ]
            if !message.isUser,
               let responseItemID = Self.assistantResponseItemID(for: message) {
                item["id"] = responseItemID
                item["status"] = "completed"
            }
            payload.append(item)
        }
        return payload
    }

    static func requestContent(for message: ChatRequestSourceMessage) -> String {
        guard !message.isUser else {
            return message.content
        }
        if let snapshot = message.requestContentSnapshot,
           !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return snapshot
        }
        return makeAssistantRequestContent(
            content: assistantTextContent(for: message),
            toolActivityPlacements: message.toolActivityPlacements
        )
    }

    static func assistantTextContent(for message: ChatRequestSourceMessage) -> String {
        let text = message.assistantSegments
            .filter { $0.kind == .text }
            .map(\.text)
            .joined()
        if !text.isEmpty || !message.assistantSegments.isEmpty {
            return text
        }
        return message.content.extractThinkParts().body
    }

    private static func assistantResponseItemID(for message: ChatRequestSourceMessage) -> String? {
        message.assistantSegments.lazy
            .filter { $0.kind == .text }
            .compactMap(\.itemID)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("output_index:") }
    }

    static func makeAssistantRequestContent(
        content: String,
        toolActivityPlacements: [ChatToolActivityPlacement]
    ) -> String {
        let toolContext = ChatToolContextTranscriptFormatter.transcript(for: toolActivityPlacements)
        guard !toolContext.isEmpty else {
            return content
        }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return toolContext
        }
        return "\(content)\n\n\(toolContext)"
    }

    @discardableResult
    static func refreshAssistantRequestSnapshotIfNeeded(
        _ message: ChatMessage,
        placements: [ChatToolActivityPlacement]? = nil
    ) -> Bool {
        guard !message.isUser else { return false }
        let persistentPlacements = (placements ?? message.toolActivityPlacements)
            .filter { $0.activity.phase.isPersistentToolTracePhase }
        let nextSnapshot = persistentPlacements.isEmpty ? nil : makeAssistantRequestContent(
            content: message.assistantText,
            toolActivityPlacements: persistentPlacements
        )
        let canUpdateSnapshot = message.isActive || message.streamCompletedAt == nil || message.requestContentSnapshot == nil
        guard canUpdateSnapshot, message.requestContentSnapshot != nextSnapshot else { return false }
        message.requestContentSnapshot = nextSnapshot
        return true
    }
}

private enum ChatToolContextTranscriptFormatter {
    static let untrustedDataInstruction = ChatToolDefinitions.untrustedResultInstruction

    static func transcript(for placements: [ChatToolActivityPlacement]) -> String {
        let activities = deduplicatedActivities(from: placements)
        guard !activities.isEmpty else {
            return ""
        }

        var lines = [
            "[Tool context]",
            untrustedDataInstruction
        ]
        for activity in activities {
            lines.append("- \(activity.title) (\(activity.toolName)): \(activity.phase.rawValue)")
            if let summary = trimmed(activity.summary),
               !summary.isEmpty {
                lines.append("  Summary: \(summary)")
            }
            if let request = activity.authorizationRequest {
                lines.append("  Authorization: \(request.title) - \(request.operationKind.rawValue)")
                if !request.argumentsSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("  Arguments: \(request.argumentsSummary)")
                }
            }
            if let modelRequestPayload = activity.modelRequestPayload,
               !modelRequestPayload.isEmpty {
                lines.append("  Request payload: \(stableCompactJSONString(JSONValue.object(modelRequestPayload)))")
            }
            if let resultPayload = activity.resultPayload,
               !resultPayload.isEmpty {
                lines.append("  Result payload: \(stableCompactJSONString(JSONValue.object(resultPayload)))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func deduplicatedActivities(
        from placements: [ChatToolActivityPlacement]
    ) -> [ChatToolActivity] {
        var seen: Set<String> = []
        var activities: [ChatToolActivity] = []
        for placement in placements {
            guard !seen.contains(placement.activity.id) else { continue }
            seen.insert(placement.activity.id)
            activities.append(placement.activity)
        }
        return activities
    }

    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableCompactJSONString(_ value: JSONValue) -> String {
        let object = value.jsonObject
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return value.compactJSONString
        }
        return string
    }
}
