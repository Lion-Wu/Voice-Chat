//
//  ChatView+Lifecycle.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import SwiftUI

extension ChatView {
    func handleChatViewAppear() {
        initialRenderCoordinator.begin()
        prepareSessionPresentation()
    }

    func handleChatViewDisappear() {
        visibleMessageController.cancelHydration()
        scrollInteractionState.clearNavigation()
        cancelOverflowTransitionScroll()
        expectAssistantResponseHaptics = false
        didTriggerResponseStartHaptic = false
#if os(iOS) || os(macOS) || os(visionOS)
        imageImportDriver.cancelAll()
        imageImportDriver.cleanupPendingPreview()
#endif
    }

    func handleSessionTransition() {
        initialRenderCoordinator.begin()
        prepareSessionPresentation()
    }

    private func prepareSessionPresentation() {
        resetScrollMetricsForSessionTransition()
        refreshVisibleMessages(hydrating: true)
        scheduleSearchNavigationIfNeeded(chatSessionsViewModel.searchNavigationTarget)
    }

    func handleBranchTransition() {
        // Branch snapshots are replaced atomically by the visible-message
        // controller. Keep the current snapshot on screen while any missing
        // fingerprints are prepared instead of restarting the initial
        // presentation gate and blanking the entire conversation.
        refreshVisibleMessages()
    }

    func handleVisibleMessageCountChange() {
        if consumeScrollToBottomAfterSendIfNeeded() {
            return
        }
        if attemptSearchTargetScroll() {
            return
        }
        if !scrollInteractionState.hasSearchInterruption(
            currentTarget: currentSearchNavigationTarget()
        ), !showScrollToBottomButton {
            scrollToBottom(animated: initialRenderCoordinator.isReady)
        }
    }

    func handleInitialContentReady() {
        guard initialRenderCoordinator.isReady else { return }
        if attemptSearchTargetScroll(animated: false) {
            return
        }
        if !scrollInteractionState.hasSearchInterruption(
            currentTarget: currentSearchNavigationTarget()
        ) {
            scrollToBottom(animated: false)
        }
    }

    func handleScrollProxyReady(_ proxy: ScrollViewProxy, availableWidth: CGFloat) {
        updateAvailableMessageWidth(availableWidth)
        scrollProxy = proxy
        DispatchQueue.main.async {
            if !attemptSearchTargetScroll(),
               !scrollInteractionState.hasSearchInterruption(
                   currentTarget: currentSearchNavigationTarget()
               ) {
                if !initialRenderCoordinator.isReady {
                    scrollToBottom(animated: false)
                    return
                }
                if consumeScrollToBottomAfterSendIfNeeded(animated: false) {
                    return
                }
                if shouldUseBottomScrollAnchor {
                    scrollToBottom(animated: false)
                }
            }
        }
    }

    var textHapticsEnabled: Bool {
        !voiceOverlayVM.isPresented
    }

    func triggerTextHaptic(_ event: AppHapticEvent) {
        guard textHapticsEnabled else { return }
        AppHaptics.trigger(event)
    }
}
