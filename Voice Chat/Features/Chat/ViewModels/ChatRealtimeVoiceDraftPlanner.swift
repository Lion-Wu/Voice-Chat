//
//  ChatRealtimeVoiceDraftPlanner.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

enum ChatRealtimeVoiceDraftPlanningResult {
    case accepted(QueuedChatDraft)
    case rejected(userFacingError: String?)
}

struct ChatRealtimeVoiceDraftPlanner {
    static func plan(
        text: String,
        imageAttachments: [ChatImageAttachment],
        supportsImageInputs: Bool,
        hasExistingImageContext: Bool,
        maxImageAttachments: Int = ChatImageAttachmentLimits.maximumAttachmentCount
    ) -> ChatRealtimeVoiceDraftPlanningResult {
        let capturedAttachments = Array(imageAttachments.prefix(maxImageAttachments))
        if !supportsImageInputs && (!capturedAttachments.isEmpty || hasExistingImageContext) {
            return .rejected(userFacingError: NSLocalizedString(
                "This conversation contains images, but the selected model only accepts text.",
                comment: "Shown when realtime voice mode cannot send because the selected model does not support image input"
            ))
        }

        let attachments = supportsImageInputs ? capturedAttachments : []
        let draft = QueuedChatDraft(text: text, imageAttachments: attachments)
        guard !draft.isEmpty else {
            return .rejected(userFacingError: nil)
        }

        return .accepted(draft)
    }
}
