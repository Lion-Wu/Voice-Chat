//
//  ChatAssistantDeltaAppender.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatAssistantDeltaAppendResult {
    let message: ChatMessage
    let fingerprint: ContentFingerprint
    let didCreateMessage: Bool
    let didResolvePendingAssistantParent: Bool
}

enum ChatAssistantDeltaAppender {
    static func append(
        piece: String,
        to session: ChatSession,
        currentAssistantMessageID: UUID?,
        pendingAssistantParentMessageID: UUID?,
        streamingAssistantMessageID: UUID?,
        streamingAssistantFingerprint: ContentFingerprint?,
        messageLookup: [UUID: ChatMessage],
        fallbackParent: () -> ChatMessage?,
        now: Date
    ) -> ChatAssistantDeltaAppendResult {
        if let id = currentAssistantMessageID,
           let existing = messageLookup[id] {
            let previousFingerprint = (streamingAssistantMessageID == existing.id) ? streamingAssistantFingerprint : nil
            existing.content += piece
            let fingerprint = previousFingerprint?.appending(piece) ?? ContentFingerprint.make(existing.content)
            return ChatAssistantDeltaAppendResult(
                message: existing,
                fingerprint: fingerprint,
                didCreateMessage: false,
                didResolvePendingAssistantParent: false
            )
        }

        let message = ChatMessage(
            content: piece,
            isUser: false,
            isActive: true,
            createdAt: now,
            session: session
        )
        let parent: ChatMessage?
        let didResolvePendingParent: Bool
        if let parentID = pendingAssistantParentMessageID,
           let resolved = messageLookup[parentID] {
            parent = resolved
            didResolvePendingParent = true
        } else {
            parent = fallbackParent()
            didResolvePendingParent = false
        }

        if let parent {
            message.parentMessage = parent
            parent.activeChildMessageID = message.id
        } else {
            session.activeRootMessageID = message.id
        }
        session.messages.append(message)

        return ChatAssistantDeltaAppendResult(
            message: message,
            fingerprint: ContentFingerprint.make(piece),
            didCreateMessage: true,
            didResolvePendingAssistantParent: didResolvePendingParent
        )
    }
}
