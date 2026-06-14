//
//  ChatQueuedDraftCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatQueuedDraftUnsupportedImagePolicy: Equatable {
    let supportsImageInputs: Bool
    let activeBranchContainsImageInputs: Bool

    func shouldWarn(about draft: QueuedChatDraft) -> Bool {
        guard !draft.isEmpty else { return false }
        guard !supportsImageInputs else { return false }
        if !draft.imageAttachments.isEmpty {
            return true
        }
        return activeBranchContainsImageInputs
    }
}

enum ChatQueuedDraftSendDecision: Equatable {
    case missingDraft
    case needsUnsupportedImageConfirmation(UUID)
    case send(QueuedChatDraft)
}

enum ChatQueuedDraftAutostartDecision: Equatable {
    case idle
    case blockedByActiveRequest
    case needsUnsupportedImageConfirmation(UUID)
    case start(QueuedChatDraft)
}

struct ChatQueuedDraftCoordinator {
    private(set) var drafts: [QueuedChatDraft] = []
    private(set) var pendingUnsupportedImageDraftID: UUID?

    private var editor = QueuedDraftEditCoordinator()

    var hasDrafts: Bool {
        !drafts.isEmpty
    }

    var isEditing: Bool {
        editor.isEditing
    }

    func draft(id: UUID) -> QueuedChatDraft? {
        drafts.first { $0.id == id }
    }

    func canSendAsTextOnly(id: UUID) -> Bool {
        guard let draft = draft(id: id) else { return false }
        return !draft.trimmedText.isEmpty
    }

    mutating func requestUnsupportedImageConfirmation(
        for id: UUID,
        policy: ChatQueuedDraftUnsupportedImagePolicy
    ) {
        guard let draft = draft(id: id) else {
            pendingUnsupportedImageDraftID = nil
            return
        }
        pendingUnsupportedImageDraftID = policy.shouldWarn(about: draft) ? id : nil
    }

    mutating func dismissUnsupportedImageConfirmation() {
        pendingUnsupportedImageDraftID = nil
    }

    mutating func enqueue(_ draft: QueuedChatDraft) {
        if !editor.commitEditedDraft(draft, into: &drafts) {
            drafts.append(draft)
        }
    }

    mutating func remove(id: UUID) {
        drafts.removeAll { $0.id == id }
        clearPendingUnsupportedImageConfirmation(matching: id)
    }

    mutating func beginEditing(id: UUID) -> QueuedChatDraft? {
        guard let draft = editor.beginEditing(id: id, in: &drafts) else { return nil }
        clearPendingUnsupportedImageConfirmation(matching: id)
        return draft
    }

    mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        drafts.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    mutating func prepareManualSend(
        id: UUID,
        ignoringUnsupportedImageInputs: Bool,
        policy: ChatQueuedDraftUnsupportedImagePolicy
    ) -> ChatQueuedDraftSendDecision {
        guard let draft = draft(id: id) else { return .missingDraft }

        if policy.shouldWarn(about: draft) && !ignoringUnsupportedImageInputs {
            pendingUnsupportedImageDraftID = id
            return .needsUnsupportedImageConfirmation(id)
        }

        pendingUnsupportedImageDraftID = nil
        return .send(draft)
    }

    mutating func removeAfterSend(id: UUID, didSend: Bool) {
        guard didSend, let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts.remove(at: index)
    }

    mutating func prepareAutostart(
        hasActiveTextRequest: Bool,
        policy: ChatQueuedDraftUnsupportedImagePolicy
    ) -> ChatQueuedDraftAutostartDecision {
        guard !hasActiveTextRequest else { return .blockedByActiveRequest }
        guard let draft = drafts.first else { return .idle }

        if policy.shouldWarn(about: draft) {
            pendingUnsupportedImageDraftID = draft.id
            return .needsUnsupportedImageConfirmation(draft.id)
        }

        clearPendingUnsupportedImageConfirmation(matching: draft.id)
        return .start(draft)
    }

    mutating func removeAutostartedDraft(id: UUID, didSend: Bool) {
        guard didSend, drafts.first?.id == id else { return }
        drafts.removeFirst()
    }

    mutating func restoreEditedDraft() -> Bool {
        editor.restoreEditedDraft(into: &drafts)
    }

    mutating func clearEditing() {
        editor.clear()
    }

    private mutating func clearPendingUnsupportedImageConfirmation(matching id: UUID) {
        if pendingUnsupportedImageDraftID == id {
            pendingUnsupportedImageDraftID = nil
        }
    }
}
