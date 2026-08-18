//
//  ChatVisibleMessageController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Combine
import Foundation

@MainActor
final class ChatVisibleMessageController: ObservableObject {
    typealias FingerprintBuilder = @Sendable (
        [(UUID, String)]
    ) async -> [UUID: ContentFingerprint]

    @Published private var publishedState = PublishedState()

    var visibleMessages: [ChatMessage] {
        publishedState.visibleMessages
    }

    var fingerprintCache: [UUID: ContentFingerprint] {
        publishedState.fingerprintCache
    }

    var isHydratingSession: Bool {
        publishedState.isHydratingSession
    }

    private var state = ChatVisibleMessageHydrationState()
    private var pendingRefresh: PendingRefresh?
    private let fingerprintBuilder: FingerprintBuilder
    private var onHydrationStateChange: @MainActor @Sendable (Bool) -> Void = { _ in }

    init(fingerprintBuilder: FingerprintBuilder? = nil) {
        self.fingerprintBuilder = fingerprintBuilder ?? { snapshots in
            await Task.detached(priority: .userInitiated) {
                Self.buildFingerprints(from: snapshots)
            }.value
        }
    }

    func refreshVisibleMessages(
        orderedMessages: [ChatMessage],
        editingBaseMessageID: UUID?,
        sessionID: UUID,
        hydrating: Bool = false,
        onVisibleCountChange: @MainActor @Sendable @escaping (Int) -> Void,
        onHydrationStateChange: @MainActor @Sendable @escaping (Bool) -> Void = { _ in }
    ) {
        self.onHydrationStateChange = onHydrationStateChange
        if !hydrating, state.deferRefreshIfHydrating() {
            pendingRefresh = PendingRefresh(
                ownerToken: state.refreshGeneration,
                orderedMessages: orderedMessages,
                editingBaseMessageID: editingBaseMessageID,
                sessionID: sessionID,
                onVisibleCountChange: onVisibleCountChange
            )
            publishStateSnapshot()
            return
        }
        if !hydrating {
            pendingRefresh = nil
        }

        let token = state.nextRefreshToken()
        if hydrating {
            beginHydration(
                orderedMessages: orderedMessages,
                editingBaseMessageID: editingBaseMessageID,
                sessionID: sessionID,
                token: token,
                onVisibleCountChange: onVisibleCountChange
            )
            return
        }

        let newVisible = ChatVisibleMessagesCoordinator.visibleMessages(
            from: orderedMessages,
            editingBaseMessageID: editingBaseMessageID
        )

        updateVisibleMessages(newVisible, sessionID: sessionID, token: token, onVisibleCountChange: onVisibleCountChange)
    }

    func applyContentFingerprintUpdate(messageID: UUID, fingerprint: ContentFingerprint) {
        state.applyContentFingerprintUpdate(messageID: messageID, fingerprint: fingerprint)
        publishStateSnapshot()
    }

    func cancelHydration() {
        pendingRefresh = nil
        state.cancelHydration()
        onHydrationStateChange(false)
        publishStateSnapshot()
    }

    private func beginHydration(
        orderedMessages: [ChatMessage],
        editingBaseMessageID: UUID?,
        sessionID: UUID,
        token: UUID,
        onVisibleCountChange: @MainActor @Sendable @escaping (Int) -> Void
    ) {
        let target = ChatVisibleMessagesCoordinator.visibleMessages(
            from: orderedMessages,
            editingBaseMessageID: editingBaseMessageID
        )

        pendingRefresh = nil
        state.beginHydration(token: token)
        onHydrationStateChange(true)
        publishStateSnapshot()
        MessageRenderCache.shared.clear()

        let snapshots = ChatVisibleMessagesCoordinator.fingerprintSnapshots(from: target)
        let buildFingerprints = fingerprintBuilder
        let fingerprintTask = Task {
            await buildFingerprints(snapshots)
        }

        state.hydrationTask = Task { @MainActor [weak self, target, snapshots, fingerprintTask, token] in
            guard let self else { return }
            let chunkSize = 48
            var idx = 0

            while idx < target.count {
                if Task.isCancelled || !state.shouldApply(token: token) { break }
                let upper = min(idx + chunkSize, target.count)
                let slice = target[idx..<upper]
                state.appendHydratedMessages(slice)
                publishStateSnapshot()
                idx = upper
                if target.count > chunkSize {
                    await Task.yield()
                }
            }

            guard !Task.isCancelled, state.shouldApply(token: token) else {
                fingerprintTask.cancel()
                return
            }

            let fingerprints = await fingerprintTask.value
            guard !Task.isCancelled,
                  state.shouldApply(token: token) else {
                return
            }
            state.applyHydratedFingerprints(fingerprints)
            finalizeVisibleState(targetCount: target.count, sessionID: sessionID, onVisibleCountChange: onVisibleCountChange)
            prewarmThinkParts(for: snapshots)

            guard state.finishHydration(token: token) else { return }
            onHydrationStateChange(false)
            publishStateSnapshot()

            if state.consumePendingRefreshAfterHydration() {
                let refresh = pendingRefresh.flatMap { pending in
                    pending.ownerToken == token ? pending : nil
                } ?? PendingRefresh(
                    ownerToken: token,
                    orderedMessages: orderedMessages,
                    editingBaseMessageID: editingBaseMessageID,
                    sessionID: sessionID,
                    onVisibleCountChange: onVisibleCountChange
                )
                pendingRefresh = nil
                publishStateSnapshot()
                refreshVisibleMessages(
                    orderedMessages: refresh.orderedMessages,
                    editingBaseMessageID: refresh.editingBaseMessageID,
                    sessionID: refresh.sessionID,
                    onVisibleCountChange: refresh.onVisibleCountChange
                )
            }
        }
        publishStateSnapshot()
    }

    private func updateVisibleMessages(
        _ newVisible: [ChatMessage],
        sessionID: UUID,
        token: UUID,
        onVisibleCountChange: @MainActor @Sendable @escaping (Int) -> Void
    ) {
        let newVisibleCopy = newVisible
        let plan = ChatVisibleMessagesCoordinator.fingerprintPlan(
            for: newVisibleCopy,
            cache: state.fingerprintCache
        )

        if plan.missingSnapshots.isEmpty {
            state.applyVisibleMessagesWithoutMissingFingerprints(
                newVisibleCopy,
                visibleIDs: plan.visibleIDs
            )
            finalizeVisibleState(targetCount: newVisibleCopy.count, sessionID: sessionID, onVisibleCountChange: onVisibleCountChange)
            publishStateSnapshot()
            return
        }

        Task { @MainActor [weak self, plan, newVisibleCopy, token] in
            guard let self else { return }
            let newFingerprints = await fingerprintBuilder(
                plan.missingSnapshots
            )
            guard state.shouldApply(token: token) else { return }

            state.applyVisibleMessagesWithMissingFingerprints(
                newVisibleCopy,
                newFingerprints: newFingerprints,
                visibleIDs: plan.visibleIDs
            )
            finalizeVisibleState(targetCount: newVisibleCopy.count, sessionID: sessionID, onVisibleCountChange: onVisibleCountChange)
            publishStateSnapshot()
        }
    }

    private func finalizeVisibleState(
        targetCount: Int,
        sessionID: UUID,
        onVisibleCountChange: @MainActor @Sendable (Int) -> Void
    ) {
        if state.shouldReportVisibleCount(targetCount: targetCount, sessionID: sessionID) {
            onVisibleCountChange(targetCount)
        }
    }

    private func prewarmThinkParts(for snapshots: [(UUID, String)]) {
        let enriched = snapshots.compactMap { entry -> (UUID, String, ContentFingerprint)? in
            guard let fp = state.fingerprintCache[entry.0] else { return nil }
            return (entry.0, entry.1, fp)
        }
        guard !enriched.isEmpty else { return }

        Task.detached(priority: .utility) {
            MessageRenderCache.shared.prewarmThinkParts(enriched)
        }
    }

    private func publishStateSnapshot() {
        let next = PublishedState(
            visibleMessages: state.visibleMessages,
            fingerprintCache: state.fingerprintCache,
            isHydratingSession: state.isHydratingSession
        )
        guard !publishedState.isEquivalent(to: next) else { return }
        publishedState = next
    }

    nonisolated private static func buildFingerprints(from snapshots: [(UUID, String)]) -> [UUID: ContentFingerprint] {
        var map: [UUID: ContentFingerprint] = [:]
        map.reserveCapacity(snapshots.count)
        for snap in snapshots {
            map[snap.0] = ContentFingerprint.make(snap.1)
        }
        return map
    }
}

private struct PublishedState {
    var visibleMessages: [ChatMessage] = []
    var fingerprintCache: [UUID: ContentFingerprint] = [:]
    var isHydratingSession = false

    func isEquivalent(to other: PublishedState) -> Bool {
        guard isHydratingSession == other.isHydratingSession,
              fingerprintCache == other.fingerprintCache,
              visibleMessages.count == other.visibleMessages.count else {
            return false
        }
        return zip(visibleMessages, other.visibleMessages).allSatisfy {
            $0.id == $1.id && $0 === $1
        }
    }
}

private struct PendingRefresh {
    let ownerToken: UUID
    let orderedMessages: [ChatMessage]
    let editingBaseMessageID: UUID?
    let sessionID: UUID
    let onVisibleCountChange: @MainActor @Sendable (Int) -> Void
}
