//
//  ChatTurnDraftPlanner.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatTurnDraftPlan: Equatable, Sendable {
    let text: String
    let imageAttachments: [ChatImageAttachment]
    let editingBaseMessageID: UUID?
    let clearComposerAfterSend: Bool
}

enum ChatTurnDraftRejection: Equatable, Sendable {
    case emptyDraft
    case activeTextRequest
    case unsupportedImageInputContext
    case emptyAfterFilteringUnsupportedImages
}

enum ChatTurnDraftPlanningResult: Equatable, Sendable {
    case accepted(ChatTurnDraftPlan)
    case rejected(ChatTurnDraftRejection)
}

struct ChatTurnDraftPlanner {
    static func plan(
        draft: QueuedChatDraft,
        hasActiveTextRequest: Bool,
        supportsImageInputs: Bool,
        hasImageInputContext: Bool,
        ignoringUnsupportedImageInputs: Bool,
        clearComposerAfterSend: Bool
    ) -> ChatTurnDraftPlanningResult {
        let trimmedText = draft.trimmedText
        let draftAttachments = draft.imageAttachments
        guard !trimmedText.isEmpty || !draftAttachments.isEmpty else {
            return .rejected(.emptyDraft)
        }
        guard !hasActiveTextRequest else {
            return .rejected(.activeTextRequest)
        }

        if hasImageInputContext && !supportsImageInputs && !ignoringUnsupportedImageInputs {
            return .rejected(.unsupportedImageInputContext)
        }

        let attachmentsForMessage = supportsImageInputs ? draftAttachments : []
        guard !trimmedText.isEmpty || !attachmentsForMessage.isEmpty else {
            return .rejected(.emptyAfterFilteringUnsupportedImages)
        }

        return .accepted(ChatTurnDraftPlan(
            text: trimmedText,
            imageAttachments: attachmentsForMessage,
            editingBaseMessageID: draft.editingBaseMessageID,
            clearComposerAfterSend: clearComposerAfterSend
        ))
    }
}
