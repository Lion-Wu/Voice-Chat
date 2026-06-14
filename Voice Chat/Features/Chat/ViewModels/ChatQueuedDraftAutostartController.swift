//
//  ChatQueuedDraftAutostartController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

@MainActor
final class ChatQueuedDraftAutostartController {
    private var task: Task<Void, Never>?

    var isScheduled: Bool {
        task != nil
    }

    deinit {
        task?.cancel()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func schedule(
        decision: ChatQueuedDraftAutostartDecision,
        canStart: @MainActor @Sendable @escaping (QueuedChatDraft) -> Bool,
        send: @MainActor @Sendable @escaping (QueuedChatDraft) -> Bool,
        complete: @MainActor @Sendable @escaping (_ id: UUID, _ didSend: Bool) -> Void
    ) {
        cancel()
        guard case let .start(draft) = decision else { return }

        task = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            defer { task = nil }

            guard canStart(draft) else { return }

            let didSend = send(draft)
            complete(draft.id, didSend)
        }
    }
}
