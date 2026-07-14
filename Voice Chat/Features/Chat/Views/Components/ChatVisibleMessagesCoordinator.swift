//
//  ChatVisibleMessagesCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatVisibleMessageFingerprintPlan: Sendable {
    let visibleIDs: Set<UUID>
    let missingSnapshots: [(UUID, String)]
}

enum ChatVisibleMessagesCoordinator {
    static func visibleMessages(
        from orderedMessages: [ChatMessage],
        editingBaseMessageID: UUID?
    ) -> [ChatMessage] {
        guard let editingBaseMessageID,
              let index = orderedMessages.firstIndex(where: { $0.id == editingBaseMessageID }) else {
            return orderedMessages
        }

        return Array(orderedMessages.prefix(index))
    }

    static func fingerprintSnapshots(from messages: [ChatMessage]) -> [(UUID, String)] {
        messages.map { ($0.id, $0.renderFingerprintSource) }
    }

    static func visibleIDs(in messages: [ChatMessage]) -> Set<UUID> {
        Set(messages.map(\.id))
    }

    static func fingerprintPlan(
        for messages: [ChatMessage],
        cache: [UUID: ContentFingerprint]
    ) -> ChatVisibleMessageFingerprintPlan {
        let visibleIDs = visibleIDs(in: messages)
        let missingSnapshots = messages
            .filter { cache[$0.id] == nil }
            .map { ($0.id, $0.renderFingerprintSource) }

        return ChatVisibleMessageFingerprintPlan(
            visibleIDs: visibleIDs,
            missingSnapshots: missingSnapshots
        )
    }

    static func pruneFingerprints(
        _ cache: [UUID: ContentFingerprint],
        keepingOnly visibleIDs: Set<UUID>
    ) -> [UUID: ContentFingerprint] {
        var out: [UUID: ContentFingerprint] = [:]
        out.reserveCapacity(min(cache.count, visibleIDs.count))
        for id in visibleIDs {
            if let fingerprint = cache[id] {
                out[id] = fingerprint
            }
        }
        return out
    }

    static func fingerprintsByMergingComputed(
        _ computed: [UUID: ContentFingerprint],
        liveUpdates: [UUID: ContentFingerprint]
    ) -> [UUID: ContentFingerprint] {
        computed.merging(liveUpdates) { _, newer in newer }
    }

    static func fingerprintsByAddingMissing(
        _ newFingerprints: [UUID: ContentFingerprint],
        to cache: [UUID: ContentFingerprint],
        keepingOnly visibleIDs: Set<UUID>
    ) -> [UUID: ContentFingerprint] {
        var merged = pruneFingerprints(cache, keepingOnly: visibleIDs)
        for (id, fingerprint) in newFingerprints {
            if merged[id] == nil {
                merged[id] = fingerprint
            }
        }
        return merged
    }

    static func shouldReportVisibleCount(
        targetCount: Int,
        sessionID: UUID,
        lastReportedVisibleCount: Int,
        lastReportedSessionID: UUID?
    ) -> Bool {
        targetCount != lastReportedVisibleCount || sessionID != lastReportedSessionID
    }
}
