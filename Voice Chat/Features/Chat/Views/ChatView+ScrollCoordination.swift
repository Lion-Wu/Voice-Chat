//
//  ChatView+ScrollCoordination.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import SwiftUI

extension ChatView {
    var visibleMessages: [ChatMessage] {
        visibleMessageController.visibleMessages
    }

    var isHydratingSession: Bool {
        visibleMessageController.isHydratingSession
    }

    func refreshVisibleMessages(hydrating: Bool = false) {
        visibleMessageController.refreshVisibleMessages(
            orderedMessages: viewModel.orderedMessagesCached(),
            editingBaseMessageID: viewModel.editingBaseMessageID,
            sessionID: viewModel.chatSession.id,
            hydrating: hydrating,
            onVisibleCountChange: onMessagesCountChange
        )
    }

    func visibleSearchText(for message: ChatMessage) -> String {
        message.assistantText
    }

    func visibleSearchSnapshots() -> [ChatSearchScrollMessageSnapshot] {
        visibleMessages.map {
            ChatSearchScrollMessageSnapshot(id: $0.id, searchText: visibleSearchText(for: $0))
        }
    }

    func currentSearchNavigationTarget() -> ChatSearchNavigationTarget? {
        guard let target = chatSessionsViewModel.searchNavigationTarget,
              target.sessionID == viewModel.chatSession.id else {
            return nil
        }
        return target
    }

    func searchHighlightQuery(for message: ChatMessage) -> String? {
        scrollInteractionState.highlightQuery(
            for: message.id,
            currentTarget: currentSearchNavigationTarget()
        )
    }

    func scheduleSearchNavigationIfNeeded(_ target: ChatSearchNavigationTarget?) {
        guard scrollInteractionState.scheduleSearchNavigationIfNeeded(
            target,
            sessionID: viewModel.chatSession.id
        ) else { return }

        cancelOverflowTransitionScroll()
        _ = attemptSearchTargetScroll()
    }

    func resetScrollMetricsForSessionTransition() {
        scrollState.resetForSessionTransition()
    }

    func scrollToBottomAfterOverflowTransitionIfNeeded(wasPastComposerOverflowThreshold: Bool) {
        guard canActivateComposerOverflowBottomAnchor else { return }
        guard !wasPastComposerOverflowThreshold, shouldTriggerComposerOverflowScroll else { return }
        guard !scrollInteractionState.hasSearchInterruption(currentTarget: currentSearchNavigationTarget()) else {
            return
        }

        scrollState.requestOverflowTransitionScrollToBottom()
    }

    func cancelOverflowTransitionScroll() {
        scrollState.cancelOverflowTransitionScroll()
    }

    @discardableResult
    func consumeOverflowTransitionScrollToBottomIfNeeded() -> Bool {
        scrollToBottomForOverflowTransitionIfReady()
    }

    @discardableResult
    func scrollToBottomForOverflowTransitionIfReady() -> Bool {
        let decision = scrollState.consumeOverflowTransitionScrollToBottomIfReady(
            metrics: currentScrollMetrics,
            hasSearchInterruption: scrollInteractionState.hasSearchInterruption(
                currentTarget: currentSearchNavigationTarget()
            ),
            scrollProxyAvailable: scrollProxy != nil
        )
        guard decision == .scrollToBottom else {
            return false
        }

        scrollToBottom(animated: false)
        return true
    }

    func requestScrollToBottomAfterSend() {
        scrollState.requestScrollToBottomAfterSend(
            visibleCount: visibleMessages.count,
            bottomMessageID: visibleMessages.last?.id
        )
        scrollInteractionState.prepareScrollToBottomAfterSend()
    }

    func cancelScrollToBottomAfterSend() {
        scrollState.cancelScrollToBottomAfterSend()
    }

    @discardableResult
    func consumeScrollToBottomAfterSendIfNeeded(animated: Bool = true) -> Bool {
        guard scrollState.consumeScrollToBottomAfterSendIfReady(
            visibleCount: visibleMessages.count,
            bottomMessageID: visibleMessages.last?.id,
            scrollProxyAvailable: scrollProxy != nil
        ) else { return false }

        scrollToBottom(animated: animated)
        return true
    }

    @discardableResult
    func attemptSearchTargetScroll() -> Bool {
        guard let decision = ChatSearchScrollCoordinator.resolveScrollTarget(
            pending: scrollInteractionState.pendingSearchScrollTarget,
            sessionID: viewModel.chatSession.id,
            visibleMessages: visibleSearchSnapshots()
        ),
              let proxy = scrollProxy else {
            return false
        }

        scrollInteractionState.applySearchScrollDecision(decision)
        let anchorY = CGFloat(decision.anchorY)
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(decision.messageID, anchor: UnitPoint(x: 0.5, y: anchorY))
        }
        scheduleSearchScrollReanchor(delayNanoseconds: 90_000_000)
        return true
    }

    func clearSearchScrollLock() {
        scrollInteractionState.clearSearchScrollLock()
    }

    func reanchorSearchScroll(_ lock: ChatSearchScrollLock, animated: Bool) {
        guard let proxy = scrollProxy,
              scrollInteractionState.canReanchorSearchScroll(
                lock,
                visibleMessageIDs: Set(visibleMessages.map(\.id))
              ) else {
            return
        }

        let action = {
            proxy.scrollTo(lock.messageID, anchor: UnitPoint(x: 0.5, y: CGFloat(lock.anchorY)))
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                action()
            }
        } else {
            action()
        }
    }

    func scheduleSearchScrollReanchor(delayNanoseconds: UInt64) {
        scrollInteractionState.replaceSearchScrollReanchorTask(nil)
        guard let lock = scrollInteractionState.searchScrollLock else { return }
        let generation = lock.generation

        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let lock = scrollInteractionState.searchScrollLock,
                  lock.generation == generation,
                  !Task.isCancelled else {
                return
            }

            reanchorSearchScroll(lock, animated: false)

            if ChatSearchScrollCoordinator.shouldContinueReanchoring(lock) {
                scheduleSearchScrollReanchor(delayNanoseconds: 120_000_000)
            } else {
                scrollInteractionState.finishSearchScrollReanchoring()
            }
        }
        scrollInteractionState.replaceSearchScrollReanchorTask(task)
    }

    func extendSearchScrollLockForLayoutChange() {
        guard scrollInteractionState.extendSearchScrollLockForLayoutChange() else { return }
        scheduleSearchScrollReanchor(delayNanoseconds: 16_000_000)
    }

    func updateContentHeightIfNeeded(_ newHeight: CGFloat) {
        enqueueScrollMetricUpdate(contentHeight: max(0, newHeight))
    }

    func updateViewportHeightIfNeeded(_ newHeight: CGFloat) {
        enqueueScrollMetricUpdate(viewportHeight: max(0, newHeight))
    }

    func updateBottomAnchorIfNeeded(_ newValue: CGFloat) {
        enqueueScrollMetricUpdate(bottomAnchorMaxY: newValue)
    }

    func enqueueScrollMetricUpdate(
        contentHeight nextContentHeight: CGFloat? = nil,
        viewportHeight nextViewportHeight: CGFloat? = nil,
        bottomAnchorMaxY nextBottomAnchorMaxY: CGFloat? = nil
    ) {
        scrollState.enqueueMetricUpdate(
            contentHeight: nextContentHeight,
            viewportHeight: nextViewportHeight,
            bottomAnchorMaxY: nextBottomAnchorMaxY
        )

        applyPendingScrollMetricUpdate()
    }

    func applyPendingScrollMetricUpdate() {
        let update = scrollState.applyPendingMetricUpdate(
            messageListBottomInset: layoutMetrics.messageListBottomInset,
            threshold: scrollToBottomButtonVisibilityThreshold
        )

        if update.didUpdate {
            if update.didUpdateScrollableGeometry {
                extendSearchScrollLockForLayoutChange()
                scrollToBottomAfterOverflowTransitionIfNeeded(
                    wasPastComposerOverflowThreshold: update.wasPastComposerOverflowThreshold
                )
            }
            let didAutoScroll =
                consumeOverflowTransitionScrollToBottomIfNeeded()
                || (update.didUpdateScrollableGeometry && consumeScrollToBottomAfterSendIfNeeded(animated: false))
            if didAutoScroll {
                hideScrollToBottomButton()
            } else {
                updateScrollToBottomVisibility()
            }
        }
    }

    func scrollToBottom(animated: Bool = true) {
        guard let proxy = scrollProxy else { return }
        let action = {
            proxy.scrollTo(ScrollTarget.bottom, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
        }
    }

    func updateScrollToBottomVisibility() {
        guard currentScrollMetrics.viewportHeight > 0 else {
            hideScrollToBottomButton()
            return
        }

        let shouldShow = shouldShowScrollToBottomButtonForCurrentGeometry
        if shouldShow != scrollState.showScrollToBottomButton {
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollState.showScrollToBottomButton = shouldShow
            }
        }
    }

    func hideScrollToBottomButton() {
        if scrollState.showScrollToBottomButton {
            scrollState.showScrollToBottomButton = false
        }
    }

    func updateAvailableMessageWidth(_ width: CGFloat) {
        let cleanedWidth = max(width, 0)
        guard abs(cleanedWidth - availableMessageWidth) > 0.5 else { return }
        availableMessageWidth = cleanedWidth
    }
}
