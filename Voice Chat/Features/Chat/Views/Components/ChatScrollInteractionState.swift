//
//  ChatScrollInteractionState.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatScrollInteractionState {
    var pendingSearchScrollTarget: ChatSearchNavigationTarget?
    var activeSearchHighlightMessageID: UUID?
    var activeSearchHighlightTargetID: UUID?

    func highlightQuery(
        for messageID: UUID,
        currentTarget: ChatSearchNavigationTarget?
    ) -> String? {
        ChatSearchScrollCoordinator.highlightQuery(
            for: messageID,
            target: currentTarget,
            activeTargetID: activeSearchHighlightTargetID,
            activeMessageID: activeSearchHighlightMessageID
        )
    }

    func hasSearchInterruption(currentTarget: ChatSearchNavigationTarget?) -> Bool {
        currentTarget != nil
            || pendingSearchScrollTarget != nil
    }

    mutating func scheduleSearchNavigationIfNeeded(
        _ target: ChatSearchNavigationTarget?,
        sessionID: UUID
    ) -> Bool {
        guard let target, target.sessionID == sessionID else {
            clearNavigation()
            return false
        }

        pendingSearchScrollTarget = target
        activeSearchHighlightMessageID = target.messageID
        activeSearchHighlightTargetID = target.id
        return true
    }

    mutating func applySearchScrollDecision(_ decision: ChatSearchScrollDecision) {
        activeSearchHighlightMessageID = decision.messageID
        activeSearchHighlightTargetID = decision.targetID
        pendingSearchScrollTarget = nil
    }

    mutating func clearNavigation() {
        pendingSearchScrollTarget = nil
        activeSearchHighlightMessageID = nil
        activeSearchHighlightTargetID = nil
    }

    mutating func prepareScrollToBottomAfterSend() {
        pendingSearchScrollTarget = nil
    }
}
