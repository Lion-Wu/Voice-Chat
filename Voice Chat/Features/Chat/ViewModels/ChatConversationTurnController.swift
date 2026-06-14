//
//  ChatConversationTurnController.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation

struct ChatConversationTurnStart {
    let draftPlan: ChatTurnDraftPlan
    let userMessage: ChatMessage
    let shouldClearEditingBaseMessageID: Bool

    var shouldClearComposerAfterSend: Bool {
        draftPlan.clearComposerAfterSend
    }
}

enum ChatConversationTurnStartResult {
    case accepted(ChatConversationTurnStart)
    case rejected(ChatTurnDraftRejection)
}

@MainActor
enum ChatConversationTurnController {
    static func startTurn(
        draft: QueuedChatDraft,
        session: ChatSession,
        hasActiveTextRequest: Bool,
        supportsImageInputs: Bool,
        hasImageInputContext: Bool,
        ignoringUnsupportedImageInputs: Bool,
        clearComposerAfterSend: Bool,
        prepareForAppend: () -> Void = {},
        fallbackParent: () -> ChatMessage?,
        estimatedTokenCount: (Int) -> Int,
        createdAt now: Date = Date()
    ) -> ChatConversationTurnStartResult {
        let draftPlanResult = ChatTurnDraftPlanner.plan(
            draft: draft,
            hasActiveTextRequest: hasActiveTextRequest,
            supportsImageInputs: supportsImageInputs,
            hasImageInputContext: hasImageInputContext,
            ignoringUnsupportedImageInputs: ignoringUnsupportedImageInputs,
            clearComposerAfterSend: clearComposerAfterSend
        )
        guard case let .accepted(draftPlan) = draftPlanResult else {
            if case let .rejected(reason) = draftPlanResult {
                return .rejected(reason)
            }
            return .rejected(.emptyDraft)
        }

        prepareForAppend()

        let appendResult = ChatUserTurnAppender.append(
            plan: draftPlan,
            to: session,
            fallbackParent: fallbackParent,
            estimatedTokenCount: estimatedTokenCount,
            createdAt: now
        )

        return .accepted(ChatConversationTurnStart(
            draftPlan: draftPlan,
            userMessage: appendResult.message,
            shouldClearEditingBaseMessageID: appendResult.shouldClearEditingBaseMessageID
        ))
    }
}
