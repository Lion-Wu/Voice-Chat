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
    var searchScrollLock: ChatSearchScrollLock?
    var searchScrollReanchorTask: Task<Void, Never>?

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
            || searchScrollLock != nil
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
        searchScrollLock = ChatSearchScrollCoordinator.makeLock(
            targetID: decision.targetID,
            messageID: decision.messageID,
            anchorY: decision.anchorY
        )
    }

    mutating func clearNavigation() {
        pendingSearchScrollTarget = nil
        activeSearchHighlightMessageID = nil
        activeSearchHighlightTargetID = nil
        clearSearchScrollLock()
    }

    mutating func prepareScrollToBottomAfterSend() {
        pendingSearchScrollTarget = nil
        clearSearchScrollLock()
    }

    mutating func clearSearchScrollLock() {
        searchScrollReanchorTask?.cancel()
        searchScrollReanchorTask = nil
        searchScrollLock = nil
    }

    mutating func replaceSearchScrollReanchorTask(_ task: Task<Void, Never>?) {
        searchScrollReanchorTask?.cancel()
        searchScrollReanchorTask = task
    }

    mutating func finishSearchScrollReanchoring() {
        searchScrollLock = nil
        searchScrollReanchorTask = nil
    }

    func canReanchorSearchScroll(
        _ lock: ChatSearchScrollLock,
        visibleMessageIDs: Set<UUID>
    ) -> Bool {
        activeSearchHighlightTargetID == lock.targetID
            && visibleMessageIDs.contains(lock.messageID)
    }

    mutating func extendSearchScrollLockForLayoutChange() -> Bool {
        guard let lock = searchScrollLock else { return false }
        guard let extendedLock = ChatSearchScrollCoordinator.extendedLockForLayoutChange(lock) else {
            clearSearchScrollLock()
            return false
        }

        searchScrollLock = extendedLock
        return true
    }
}
