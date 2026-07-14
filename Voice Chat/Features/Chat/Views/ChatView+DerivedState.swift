//
//  ChatView+DerivedState.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/14.
//

import SwiftUI

extension ChatView {
    var layoutMetrics: ChatComposerLayoutMetrics {
        ChatComposerLayoutMetrics(
            textFieldHeight: textFieldHeight,
            editingBannerHeight: editingBannerHeight,
            pendingAttachmentCount: viewModel.pendingImageAttachments.count,
            queuedDraftCount: viewModel.queuedDrafts.count,
            hasQueuedDrafts: viewModel.hasQueuedDrafts,
            isEditingComposerDraft: viewModel.isEditingComposerDraft,
            hasConfigurableThinking: currentModelThinkingCapability?.isConfigurable == true
        )
    }

    var scrollToBottomButtonVisibilityThreshold: CGFloat {
        24
    }

    var currentScrollMetrics: ChatScrollMetrics {
        scrollState.metrics(
            messageListBottomInset: layoutMetrics.messageListBottomInset,
            threshold: scrollToBottomButtonVisibilityThreshold
        )
    }

    var shouldShowScrollToBottomButtonForCurrentGeometry: Bool {
        currentScrollMetrics.shouldShowScrollToBottomButton
    }

    var shouldTriggerComposerOverflowScroll: Bool {
        currentScrollMetrics.shouldTriggerComposerOverflowScroll
    }

    var canActivateComposerOverflowBottomAnchor: Bool {
        viewModel.isLoading || viewModel.isPriming || viewModel.isToolContinuationLoading
    }

    var shouldUseBottomScrollAnchor: Bool {
        scrollState.shouldUseBottomScrollAnchor(
            messageListBottomInset: layoutMetrics.messageListBottomInset,
            threshold: scrollToBottomButtonVisibilityThreshold
        )
    }

    var shouldDisplayAudioPlayer: Bool {
        audioManager.isShowingAudioPlayer && !audioManager.isRealtimeMode && !voiceOverlayVM.isPresented
    }

    var canSendDraft: Bool {
        sendCoordinator.canSendDraft
    }

    var currentModelSupportsImageInput: Bool {
        viewModel.currentModelSupportsImageInput()
    }

    var currentModelThinkingCapability: ModelThinkingCapability? {
        viewModel.currentModelThinkingCapability()
    }

    var currentThinkingOption: ModelThinkingOption? {
        viewModel.currentThinkingOption()
    }
}
