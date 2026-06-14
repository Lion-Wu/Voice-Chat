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
        resetScrollMetricsForSessionTransition()
        refreshVisibleMessages(hydrating: true)
        scheduleSearchNavigationIfNeeded(chatSessionsViewModel.searchNavigationTarget)
    }

    func handleVisibleMessageCountChange() {
        if consumeScrollToBottomAfterSendIfNeeded() {
            return
        }
        if attemptSearchTargetScroll() {
            return
        }
        if scrollInteractionState.pendingSearchScrollTarget == nil, !scrollState.showScrollToBottomButton {
            scrollToBottom()
        }
    }

    func handleScrollProxyReady(_ proxy: ScrollViewProxy, availableWidth: CGFloat) {
        updateAvailableMessageWidth(availableWidth)
        scrollProxy = proxy
        DispatchQueue.main.async {
            if !attemptSearchTargetScroll(), scrollInteractionState.pendingSearchScrollTarget == nil {
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
