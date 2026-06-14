//
//  ChatComposerDraftController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct ChatComposerDraftState: Equatable, Sendable {
    var text: String = ""
    var imageAttachments: [ChatImageAttachment] = []
    var editingBaseMessageID: UUID?

    static let empty = ChatComposerDraftState()

    init(
        text: String = "",
        imageAttachments: [ChatImageAttachment] = [],
        editingBaseMessageID: UUID? = nil
    ) {
        self.text = text
        self.imageAttachments = imageAttachments
        self.editingBaseMessageID = editingBaseMessageID
    }

    init(draft: QueuedChatDraft) {
        self.init(
            text: draft.text,
            imageAttachments: draft.imageAttachments,
            editingBaseMessageID: draft.editingBaseMessageID
        )
    }
}

enum ChatComposerDraftController {
    static func currentDraft(from state: ChatComposerDraftState) -> QueuedChatDraft? {
        let draft = QueuedChatDraft(
            text: state.text,
            imageAttachments: state.imageAttachments,
            editingBaseMessageID: state.editingBaseMessageID
        )
        return draft.isEmpty ? nil : draft
    }

    static func editingState(from message: ChatMessage) -> ChatComposerDraftState? {
        guard message.isUser else { return nil }
        return ChatComposerDraftState(
            text: message.content,
            imageAttachments: message.imageAttachments,
            editingBaseMessageID: message.id
        )
    }
}
