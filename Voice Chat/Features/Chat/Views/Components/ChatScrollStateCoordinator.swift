//
//  ChatScrollStateCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import CoreGraphics
import Foundation

struct ChatScrollMetrics: Equatable, Sendable {
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let bottomAnchorMaxY: CGFloat
    let messageListBottomInset: CGFloat
    let threshold: CGFloat

    var effectiveContentHeight: CGFloat {
        max(0, contentHeight - messageListBottomInset)
    }

    var contentDistanceBelowViewport: CGFloat {
        guard viewportHeight > 0 else { return 0 }
        return max(0, contentHeight - viewportHeight)
    }

    var bottomAnchorDistanceBelowViewport: CGFloat {
        guard viewportHeight > 0 else { return 0 }
        return max(0, bottomAnchorMaxY - viewportHeight)
    }

    var shouldShowScrollToBottomButton: Bool {
        bottomAnchorDistanceBelowViewport > threshold
    }

    var shouldTriggerComposerOverflowScroll: Bool {
        contentDistanceBelowViewport > threshold
    }

    var shouldAnchorBottom: Bool {
        guard viewportHeight > 0 else { return false }
        return effectiveContentHeight > (viewportHeight + 1)
    }
}

struct ChatScrollMetricUpdateResult: Equatable, Sendable {
    let didUpdate: Bool
    let didUpdateScrollableGeometry: Bool
    let wasPastComposerOverflowThreshold: Bool
}

enum ChatScrollOverflowDecision: Equatable, Sendable {
    case none
    case waiting
    case cancelled
    case scrollToBottom
}

private struct ChatScrollToBottomAfterSendState: Equatable, Sendable {
    var isRequested: Bool = false
    var baselineVisibleCount: Int?
    var baselineBottomMessageID: UUID?
}

struct ChatScrollState: Equatable, Sendable {
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var bottomAnchorMaxY: CGFloat = 0
    var pendingContentHeight: CGFloat?
    var pendingViewportHeight: CGFloat?
    var pendingBottomAnchorMaxY: CGFloat?
    var showScrollToBottomButton: Bool = false
    var hasActivatedComposerOverflowBottomAnchor: Bool = false
    var pendingComposerOverflowScrollToBottom: Bool = false

    private var scrollToBottomAfterSend = ChatScrollToBottomAfterSendState()

    func metrics(messageListBottomInset: CGFloat, threshold: CGFloat) -> ChatScrollMetrics {
        ChatScrollMetrics(
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            bottomAnchorMaxY: bottomAnchorMaxY,
            messageListBottomInset: messageListBottomInset,
            threshold: threshold
        )
    }

    func shouldUseBottomScrollAnchor(messageListBottomInset: CGFloat, threshold: CGFloat) -> Bool {
        metrics(messageListBottomInset: messageListBottomInset, threshold: threshold).shouldAnchorBottom
            || hasActivatedComposerOverflowBottomAnchor
    }

    mutating func resetForSessionTransition() {
        pendingContentHeight = nil
        pendingBottomAnchorMaxY = nil
        contentHeight = 0
        bottomAnchorMaxY = 0
        showScrollToBottomButton = false
        cancelOverflowTransitionScroll()
        cancelScrollToBottomAfterSend()
    }

    mutating func enqueueMetricUpdate(
        contentHeight nextContentHeight: CGFloat? = nil,
        viewportHeight nextViewportHeight: CGFloat? = nil,
        bottomAnchorMaxY nextBottomAnchorMaxY: CGFloat? = nil
    ) {
        if let nextContentHeight {
            pendingContentHeight = nextContentHeight
        }
        if let nextViewportHeight {
            pendingViewportHeight = nextViewportHeight
        }
        if let nextBottomAnchorMaxY {
            pendingBottomAnchorMaxY = nextBottomAnchorMaxY
        }
    }

    mutating func applyPendingMetricUpdate(messageListBottomInset: CGFloat, threshold: CGFloat) -> ChatScrollMetricUpdateResult {
        let wasPastComposerOverflowThreshold = metrics(
            messageListBottomInset: messageListBottomInset,
            threshold: threshold
        ).shouldTriggerComposerOverflowScroll
        var didUpdate = false
        var didUpdateScrollableGeometry = false

        if let pendingContentHeight {
            self.pendingContentHeight = nil
            if abs(pendingContentHeight - contentHeight) > 0.5 {
                contentHeight = pendingContentHeight
                didUpdate = true
                didUpdateScrollableGeometry = true
            }
        }

        if let pendingViewportHeight {
            self.pendingViewportHeight = nil
            if abs(pendingViewportHeight - viewportHeight) > 0.5 {
                viewportHeight = pendingViewportHeight
                didUpdate = true
                didUpdateScrollableGeometry = true
            }
        }

        if let pendingBottomAnchorMaxY {
            self.pendingBottomAnchorMaxY = nil
            if abs(pendingBottomAnchorMaxY - bottomAnchorMaxY) > 0.5 {
                bottomAnchorMaxY = pendingBottomAnchorMaxY
                didUpdate = true
            }
        }

        if didUpdateScrollableGeometry,
           hasActivatedComposerOverflowBottomAnchor,
           !metrics(messageListBottomInset: messageListBottomInset, threshold: threshold).shouldTriggerComposerOverflowScroll {
            cancelOverflowTransitionScroll()
        }

        return ChatScrollMetricUpdateResult(
            didUpdate: didUpdate,
            didUpdateScrollableGeometry: didUpdateScrollableGeometry,
            wasPastComposerOverflowThreshold: wasPastComposerOverflowThreshold
        )
    }

    mutating func requestOverflowTransitionScrollToBottom() {
        hasActivatedComposerOverflowBottomAnchor = true
        pendingComposerOverflowScrollToBottom = true
    }

    mutating func cancelOverflowTransitionScroll() {
        hasActivatedComposerOverflowBottomAnchor = false
        pendingComposerOverflowScrollToBottom = false
    }

    mutating func consumeOverflowTransitionScrollToBottomIfReady(
        metrics: ChatScrollMetrics,
        hasSearchInterruption: Bool,
        scrollProxyAvailable: Bool
    ) -> ChatScrollOverflowDecision {
        guard pendingComposerOverflowScrollToBottom else { return .none }
        guard metrics.shouldTriggerComposerOverflowScroll else {
            cancelOverflowTransitionScroll()
            return .cancelled
        }
        guard metrics.shouldShowScrollToBottomButton, scrollProxyAvailable else { return .waiting }
        guard !hasSearchInterruption else {
            cancelOverflowTransitionScroll()
            return .cancelled
        }

        pendingComposerOverflowScrollToBottom = false
        return .scrollToBottom
    }

    mutating func requestScrollToBottomAfterSend(visibleCount: Int, bottomMessageID: UUID?) {
        scrollToBottomAfterSend.isRequested = true
        scrollToBottomAfterSend.baselineVisibleCount = visibleCount
        scrollToBottomAfterSend.baselineBottomMessageID = bottomMessageID
    }

    mutating func cancelScrollToBottomAfterSend() {
        scrollToBottomAfterSend = ChatScrollToBottomAfterSendState()
    }

    mutating func consumeScrollToBottomAfterSendIfReady(
        visibleCount: Int,
        bottomMessageID: UUID?,
        scrollProxyAvailable: Bool
    ) -> Bool {
        guard scrollToBottomAfterSend.isRequested else { return false }
        if let baseline = scrollToBottomAfterSend.baselineVisibleCount,
           visibleCount <= baseline,
           bottomMessageID == scrollToBottomAfterSend.baselineBottomMessageID {
            return false
        }
        guard scrollProxyAvailable else { return false }

        cancelScrollToBottomAfterSend()
        return true
    }
}
