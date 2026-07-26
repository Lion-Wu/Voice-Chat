//
//  ChatView+Lifecycle.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import SwiftUI

extension ChatView {
    func handleChatViewAppear() {
        handleSessionTransition()
#if os(macOS)
        returnKeySendMonitor.register(
            isInputFocused: { isInputFocused },
            sendIfPossible: sendCoordinator.sendIfPossible
        )
#endif
    }

    func handleChatViewDisappear() {
#if os(macOS)
        returnKeySendMonitor.unregister()
#endif
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
        resetScrollMetricsForSessionTransition()
        refreshVisibleMessages(hydrating: true)
        scheduleSearchNavigationIfNeeded(chatSessionsViewModel.searchNavigationTarget)
    }

    func handleBranchTransition() {
        initialRenderCoordinator.begin()
        refreshVisibleMessages(hydrating: true)
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
        ), !scrollState.showScrollToBottomButton {
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
