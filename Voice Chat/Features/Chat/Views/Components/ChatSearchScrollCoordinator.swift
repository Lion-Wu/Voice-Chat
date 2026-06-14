//
//  ChatSearchScrollCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatSearchScrollMessageSnapshot: Equatable, Sendable {
    let id: UUID
    let searchText: String
}

struct ChatSearchScrollDecision: Equatable, Sendable {
    let targetID: UUID
    let messageID: UUID
    let anchorY: Double
}

struct ChatSearchScrollLock: Equatable, Sendable {
    let targetID: UUID
    let messageID: UUID
    let anchorY: Double
    let generation: UUID
    let hardDeadline: Date
    var settleDeadline: Date
}

enum ChatSearchScrollCoordinator {
    static func normalizedSearchText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    static func resolveScrollTarget(
        pending target: ChatSearchNavigationTarget?,
        sessionID: UUID,
        visibleMessages: [ChatSearchScrollMessageSnapshot]
    ) -> ChatSearchScrollDecision? {
        guard let target, target.sessionID == sessionID else { return nil }

        if visibleMessages.contains(where: { $0.id == target.messageID }) {
            return ChatSearchScrollDecision(
                targetID: target.id,
                messageID: target.messageID,
                anchorY: target.anchorY
            )
        }

        let normalizedQuery = normalizedSearchText(target.query)
        guard !normalizedQuery.isEmpty,
              let fallback = visibleMessages.first(where: {
                  normalizedSearchText($0.searchText).contains(normalizedQuery)
              }) else {
            return nil
        }

        return ChatSearchScrollDecision(
            targetID: target.id,
            messageID: fallback.id,
            anchorY: searchAnchorY(in: fallback.searchText, query: target.query)
        )
    }

    static func highlightQuery(
        for messageID: UUID,
        target: ChatSearchNavigationTarget?,
        activeTargetID: UUID?,
        activeMessageID: UUID?
    ) -> String? {
        guard let target,
              activeTargetID == target.id,
              activeMessageID == messageID else {
            return nil
        }
        return target.query
    }

    static func makeLock(
        targetID: UUID,
        messageID: UUID,
        anchorY: Double,
        now: Date = Date(),
        generation: UUID = UUID(),
        hardDuration: TimeInterval = 3.0,
        settleDuration: TimeInterval = 0.45
    ) -> ChatSearchScrollLock {
        ChatSearchScrollLock(
            targetID: targetID,
            messageID: messageID,
            anchorY: anchorY,
            generation: generation,
            hardDeadline: now.addingTimeInterval(hardDuration),
            settleDeadline: now.addingTimeInterval(settleDuration)
        )
    }

    static func extendedLockForLayoutChange(
        _ lock: ChatSearchScrollLock,
        now: Date = Date(),
        settleDuration: TimeInterval = 0.45
    ) -> ChatSearchScrollLock? {
        guard now < lock.hardDeadline else { return nil }

        var next = lock
        let nextSettleDeadline = min(now.addingTimeInterval(settleDuration), lock.hardDeadline)
        if nextSettleDeadline > lock.settleDeadline {
            next.settleDeadline = nextSettleDeadline
        }
        return next
    }

    static func shouldContinueReanchoring(_ lock: ChatSearchScrollLock, now: Date = Date()) -> Bool {
        now < lock.settleDeadline
    }

    static func searchAnchorY(in text: String, query: String) -> Double {
        let nsText = text as NSString
        guard nsText.length > 0 else { return 0.5 }

        let foundRange = nsText.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: NSRange(location: 0, length: nsText.length)
        )
        guard foundRange.location != NSNotFound, foundRange.length > 0 else { return 0.5 }

        let midpoint = Double(foundRange.location) + Double(foundRange.length) / 2
        if let lineAnchor = searchLineAnchorY(in: text, foundRange: foundRange) {
            return lineAnchor
        }
        return clampedSearchAnchorY(midpoint / Double(nsText.length))
    }

    private static func searchLineAnchorY(in text: String, foundRange: NSRange) -> Double? {
        guard text.contains(where: \.isNewline),
              let range = Range(foundRange, in: text) else {
            return nil
        }

        let lineIndex = text[..<range.lowerBound].reduce(0) { partial, character in
            partial + (character.isNewline ? 1 : 0)
        }
        let lineCount = text.reduce(1) { partial, character in
            partial + (character.isNewline ? 1 : 0)
        }
        guard lineCount > 1 else { return nil }
        return clampedSearchAnchorY((Double(lineIndex) + 0.5) / Double(lineCount))
    }

    private static func clampedSearchAnchorY(_ anchorY: Double) -> Double {
        min(0.95, max(0.05, anchorY))
    }
}
