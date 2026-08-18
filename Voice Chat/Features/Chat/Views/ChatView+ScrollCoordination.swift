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

    func refreshVisibleMessages(hydrating: Bool = false) {
        visibleMessageController.refreshVisibleMessages(
            orderedMessages: viewModel.orderedMessagesCached(),
            editingBaseMessageID: viewModel.editingBaseMessageID,
            sessionID: viewModel.chatSession.id,
            hydrating: hydrating,
            onVisibleCountChange: { count in
                if visibleMessageCount != count {
                    visibleMessageCount = count
                }
                onMessagesCountChange(count)
            },
            onHydrationStateChange: { isHydrating in
                if isHydratingSession != isHydrating {
                    isHydratingSession = isHydrating
                }
            }
        )
    }

    static func visibleSearchText(for message: ChatMessage) -> String {
        message.assistantText
    }

    func visibleSearchSnapshots() -> [ChatSearchScrollMessageSnapshot] {
        visibleMessages.map {
            ChatSearchScrollMessageSnapshot(id: $0.id, searchText: Self.visibleSearchText(for: $0))
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
        _ = attemptSearchTargetScroll(animated: initialRenderCoordinator.isReady)
    }

    func resetScrollMetricsForSessionTransition() {
        scrollState.resetForSessionTransition()
        showScrollToBottomButton = false
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
    func attemptSearchTargetScroll(animated: Bool = true) -> Bool {
        guard initialRenderCoordinator.isReady else {
            return false
        }
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
        let action = {
            proxy.scrollTo(decision.messageID, anchor: UnitPoint(x: 0.5, y: anchorY))
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.28)) {
                action()
            }
        } else {
            action()
        }
        return true
    }

    func updateContentHeightIfNeeded(_ newHeight: CGFloat) {
        enqueueScrollMetricUpdate(contentHeight: max(0, newHeight))
        if !initialRenderCoordinator.isReady,
           !scrollInteractionState.hasSearchInterruption(
               currentTarget: currentSearchNavigationTarget()
           ) {
            scrollToBottom(animated: false)
        }
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
        if shouldShow != showScrollToBottomButton {
            withAnimation(.easeInOut(duration: 0.2)) {
                showScrollToBottomButton = shouldShow
                scrollState.showScrollToBottomButton = shouldShow
            }
        }
    }

    func hideScrollToBottomButton() {
        if showScrollToBottomButton {
            showScrollToBottomButton = false
            scrollState.showScrollToBottomButton = false
        }
    }

    func updateAvailableMessageWidth(_ width: CGFloat) {
        let cleanedWidth = max(width, 0)
        guard abs(cleanedWidth - availableMessageWidth) > 0.5 else { return }
        availableMessageWidth = cleanedWidth
    }
}
