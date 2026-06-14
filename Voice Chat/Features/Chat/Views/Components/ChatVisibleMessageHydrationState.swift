//
//  ChatVisibleMessageHydrationState.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatVisibleMessageHydrationState {
    var visibleMessages: [ChatMessage] = []
    var fingerprintCache: [UUID: ContentFingerprint] = [:]
    var lastReportedVisibleCount: Int = 0
    var lastReportedSessionID: UUID?
    var isHydratingSession: Bool = false
    var hydrationTask: Task<Void, Never>?
    var pendingRefreshAfterHydration: Bool = false
    var refreshGeneration = UUID()

    var isHydrating: Bool {
        hydrationTask != nil || isHydratingSession
    }

    mutating func nextRefreshToken() -> UUID {
        let token = UUID()
        refreshGeneration = token
        return token
    }

    func shouldApply(token: UUID) -> Bool {
        token == refreshGeneration
    }

    mutating func deferRefreshIfHydrating() -> Bool {
        guard isHydrating else {
            pendingRefreshAfterHydration = false
            return false
        }

        pendingRefreshAfterHydration = true
        return true
    }

    mutating func beginHydration(token: UUID) {
        hydrationTask?.cancel()
        refreshGeneration = token
        isHydratingSession = true
        visibleMessages.removeAll(keepingCapacity: true)
        fingerprintCache.removeAll(keepingCapacity: true)
    }

    mutating func finishHydration() {
        isHydratingSession = false
        hydrationTask = nil
    }

    mutating func cancelHydration() {
        hydrationTask?.cancel()
        hydrationTask = nil
        isHydratingSession = false
        pendingRefreshAfterHydration = false
    }

    mutating func consumePendingRefreshAfterHydration() -> Bool {
        guard pendingRefreshAfterHydration else { return false }
        pendingRefreshAfterHydration = false
        return true
    }

    mutating func appendHydratedMessages<S: Sequence>(_ messages: S) where S.Element == ChatMessage {
        visibleMessages.append(contentsOf: messages)
    }

    mutating func applyHydratedFingerprints(_ computed: [UUID: ContentFingerprint]) {
        let liveUpdates = fingerprintCache
        fingerprintCache = ChatVisibleMessagesCoordinator.fingerprintsByMergingComputed(
            computed,
            liveUpdates: liveUpdates
        )
    }

    mutating func applyVisibleMessagesWithoutMissingFingerprints(
        _ messages: [ChatMessage],
        visibleIDs: Set<UUID>
    ) {
        fingerprintCache = ChatVisibleMessagesCoordinator.pruneFingerprints(
            fingerprintCache,
            keepingOnly: visibleIDs
        )
        visibleMessages = messages
    }

    mutating func applyVisibleMessagesWithMissingFingerprints(
        _ messages: [ChatMessage],
        newFingerprints: [UUID: ContentFingerprint],
        visibleIDs: Set<UUID>
    ) {
        fingerprintCache = ChatVisibleMessagesCoordinator.fingerprintsByAddingMissing(
            newFingerprints,
            to: fingerprintCache,
            keepingOnly: visibleIDs
        )
        visibleMessages = messages
    }

    mutating func applyContentFingerprintUpdate(messageID: UUID, fingerprint: ContentFingerprint) {
        if isHydrating {
            pendingRefreshAfterHydration = true
        }
        fingerprintCache[messageID] = fingerprint
    }

    mutating func shouldReportVisibleCount(targetCount: Int, sessionID: UUID) -> Bool {
        let shouldReport = ChatVisibleMessagesCoordinator.shouldReportVisibleCount(
            targetCount: targetCount,
            sessionID: sessionID,
            lastReportedVisibleCount: lastReportedVisibleCount,
            lastReportedSessionID: lastReportedSessionID
        )

        lastReportedVisibleCount = targetCount
        if shouldReport {
            lastReportedSessionID = sessionID
        }
        return shouldReport
    }
}
