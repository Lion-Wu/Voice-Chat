//
//  ChatViewModel+Drafts.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

@MainActor
extension ChatViewModel {
    var hasQueuedDrafts: Bool { queuedDraftCoordinator.hasDrafts }

    func shouldWarnAboutUnsupportedImageInput(for draft: QueuedChatDraft) -> Bool {
        queuedDraftUnsupportedImagePolicy().shouldWarn(about: draft)
    }

    func queuedDraft(id: UUID) -> QueuedChatDraft? {
        queuedDraftCoordinator.draft(id: id)
    }

    func requestUnsupportedImageConfirmationForQueuedDraft(id: UUID) {
        queuedDraftCoordinator.requestUnsupportedImageConfirmation(
            for: id,
            policy: queuedDraftUnsupportedImagePolicy()
        )
    }

    func dismissUnsupportedImageConfirmationForQueuedDraft() {
        queuedDraftCoordinator.dismissUnsupportedImageConfirmation()
    }

    func queuedDraftCanSendAsTextOnly(id: UUID) -> Bool {
        queuedDraftCoordinator.canSendAsTextOnly(id: id)
    }

    @discardableResult
    func enqueueCurrentDraft() -> Bool {
        guard let draft = currentComposerDraft() else { return false }
        queuedDraftCoordinator.enqueue(draft)
        clearComposerDraft()
        scheduleQueuedDraftAutostartIfNeeded()
        return true
    }

    func removeQueuedDraft(id: UUID) {
        queuedDraftCoordinator.remove(id: id)
        scheduleQueuedDraftAutostartIfNeeded()
    }

    func editQueuedDraft(id: UUID) {
        guard let draft = queuedDraftCoordinator.beginEditing(id: id) else { return }
        loadComposer(from: draft)
    }

    func moveQueuedDrafts(fromOffsets: IndexSet, toOffset: Int) {
        queuedDraftCoordinator.move(fromOffsets: fromOffsets, toOffset: toOffset)
        scheduleQueuedDraftAutostartIfNeeded()
    }

    @discardableResult
    func sendQueuedDraftNow(id: UUID, ignoringUnsupportedImageInputs: Bool = true) -> Bool {
        cancelQueuedDraftAutostart()

        let sendDecision = queuedDraftCoordinator.prepareManualSend(
            id: id,
            ignoringUnsupportedImageInputs: ignoringUnsupportedImageInputs,
            policy: queuedDraftUnsupportedImagePolicy()
        )
        guard case let .send(draft) = sendDecision else {
            return false
        }

        if hasActiveTextRequest {
            cancelCurrentRequest(autostartQueuedDraft: false)
        }

        let didSend = send(
            draft: draft,
            ignoringUnsupportedImageInputs: ignoringUnsupportedImageInputs,
            clearComposerAfterSend: false
        )

        queuedDraftCoordinator.removeAfterSend(id: id, didSend: didSend)

        return didSend
    }

    @discardableResult
    func sendMessage(ignoringUnsupportedImageInputs: Bool = false) -> Bool {
        guard let draft = currentComposerDraft() else { return false }
        return send(
            draft: draft,
            ignoringUnsupportedImageInputs: ignoringUnsupportedImageInputs,
            clearComposerAfterSend: true
        )
    }

    func beginEditUserMessage(_ message: ChatMessage) {
        guard let state = ChatComposerDraftController.editingState(from: message) else { return }
        composerDraftState = state
    }

    func cancelEditing() {
        if queuedDraftCoordinator.restoreEditedDraft() {
            clearComposerDraft()
            scheduleQueuedDraftAutostartIfNeeded()
            return
        }
        composerDraftState = .empty
    }

    func clearQueuedDraftEditingState() {
        queuedDraftCoordinator.clearEditing()
    }

    func cancelQueuedDraftAutostart() {
        queuedDraftAutostartController.cancel()
    }

    func scheduleQueuedDraftAutostartIfNeeded() {
        let autostartDecision = queuedDraftCoordinator.prepareAutostart(
            hasActiveTextRequest: hasActiveTextRequest,
            policy: queuedDraftUnsupportedImagePolicy()
        )
        queuedDraftAutostartController.schedule(
            decision: autostartDecision,
            canStart: { [weak self] draft in
                guard let self else { return false }
                guard !self.hasActiveTextRequest else { return false }
                return self.queuedDrafts.first?.id == draft.id
            },
            send: { [weak self] draft in
                guard let self else { return false }
                return self.send(
                    draft: draft,
                    ignoringUnsupportedImageInputs: false,
                    clearComposerAfterSend: false
                )
            },
            complete: { [weak self] id, didSend in
                self?.queuedDraftCoordinator.removeAutostartedDraft(id: id, didSend: didSend)
            }
        )
    }

    func clearComposerDraft() {
        composerDraftState = .empty
    }

    private func queuedDraftUnsupportedImagePolicy() -> ChatQueuedDraftUnsupportedImagePolicy {
        ChatQueuedDraftUnsupportedImagePolicy(
            supportsImageInputs: currentModelSupportsImageInput(),
            activeBranchContainsImageInputs: activeBranchContainsImageInputs(includePending: false)
        )
    }

    private func currentComposerDraft() -> QueuedChatDraft? {
        ChatComposerDraftController.currentDraft(from: composerDraftState)
    }

    private var composerDraftState: ChatComposerDraftState {
        get {
            ChatComposerDraftState(
                text: userMessage,
                imageAttachments: pendingImageAttachments,
                editingBaseMessageID: editingBaseMessageID
            )
        }
        set {
            userMessage = newValue.text
            pendingImageAttachments = newValue.imageAttachments
            editingBaseMessageID = newValue.editingBaseMessageID
        }
    }

    private func loadComposer(from draft: QueuedChatDraft) {
        composerDraftState = ChatComposerDraftState(draft: draft)
    }
}
