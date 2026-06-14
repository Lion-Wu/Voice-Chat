//
//  QueuedDraftEditCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct QueuedDraftEditCoordinator {
    private struct EditState {
        let draft: QueuedChatDraft
        let previousDraftID: UUID?
        let nextDraftID: UUID?
    }

    private var editState: EditState?

    var isEditing: Bool {
        editState != nil
    }

    mutating func beginEditing(id: UUID, in drafts: inout [QueuedChatDraft]) -> QueuedChatDraft? {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return nil }
        let previousDraftID = index > 0 ? drafts[index - 1].id : nil
        let nextDraftID = index < drafts.count - 1 ? drafts[index + 1].id : nil
        let draft = drafts.remove(at: index)
        editState = EditState(
            draft: draft,
            previousDraftID: previousDraftID,
            nextDraftID: nextDraftID
        )
        return draft
    }

    mutating func commitEditedDraft(_ draft: QueuedChatDraft, into drafts: inout [QueuedChatDraft]) -> Bool {
        guard let editState else { return false }
        var updated = draft
        updated.id = editState.draft.id
        updated.createdAt = editState.draft.createdAt
        Self.insert(
            updated,
            into: &drafts,
            previousDraftID: editState.previousDraftID,
            nextDraftID: editState.nextDraftID
        )
        self.editState = nil
        return true
    }

    mutating func restoreEditedDraft(into drafts: inout [QueuedChatDraft]) -> Bool {
        guard let editState else { return false }
        Self.insert(
            editState.draft,
            into: &drafts,
            previousDraftID: editState.previousDraftID,
            nextDraftID: editState.nextDraftID
        )
        self.editState = nil
        return true
    }

    mutating func clear() {
        editState = nil
    }

    static func insert(
        _ draft: QueuedChatDraft,
        into drafts: inout [QueuedChatDraft],
        previousDraftID: UUID?,
        nextDraftID: UUID?
    ) {
        if let nextDraftID,
           let index = drafts.firstIndex(where: { $0.id == nextDraftID }) {
            drafts.insert(draft, at: index)
            return
        }

        if let previousDraftID,
           let index = drafts.firstIndex(where: { $0.id == previousDraftID }) {
            drafts.insert(draft, at: min(index + 1, drafts.count))
            return
        }

        drafts.append(draft)
    }
}
