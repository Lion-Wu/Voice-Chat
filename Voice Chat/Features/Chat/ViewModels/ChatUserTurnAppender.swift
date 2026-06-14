//
//  ChatUserTurnAppender.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatUserTurnAppendResult {
    let message: ChatMessage
    let shouldClearEditingBaseMessageID: Bool
}

struct ChatUserTurnAppender {
    static func append(
        plan: ChatTurnDraftPlan,
        to session: ChatSession,
        fallbackParent: () -> ChatMessage?,
        estimatedTokenCount: (Int) -> Int,
        createdAt now: Date = Date()
    ) -> ChatUserTurnAppendResult {
        var shouldClearEditingBaseMessageID = false
        let parentMessage: ChatMessage?

        if let baseID = plan.editingBaseMessageID,
           let base = session.messages.first(where: { $0.id == baseID }) {
            parentMessage = base.parentMessage
            shouldClearEditingBaseMessageID = plan.clearComposerAfterSend
        } else {
            parentMessage = fallbackParent()
        }

        let userMessage = ChatMessage(
            content: plan.text,
            imageAttachments: plan.imageAttachments,
            isUser: true,
            isActive: true,
            createdAt: now,
            deltaCount: estimatedTokenCount(plan.text.count),
            tokenCountSource: ChatStreamMetricValueSource.local.rawValue,
            characterCount: plan.text.count,
            session: session
        )
        userMessage.parentMessage = parentMessage
        if let parentMessage {
            parentMessage.activeChildMessageID = userMessage.id
        } else {
            session.activeRootMessageID = userMessage.id
        }
        session.messages.append(userMessage)

        if isPlaceholderTitle(session.title), !plan.text.isEmpty {
            session.title = plan.text
        }

        return ChatUserTurnAppendResult(
            message: userMessage,
            shouldClearEditingBaseMessageID: shouldClearEditingBaseMessageID
        )
    }

    private static func isPlaceholderTitle(_ title: String) -> Bool {
        AppLocalization.localizedPlaceholderTitles().contains(title)
    }
}
