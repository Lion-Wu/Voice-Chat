//
//  ChatView+Content.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import SwiftUI

extension ChatView {
    var body: some View {
        chatViewContent
    }

    @ViewBuilder
    var chatViewContent: some View {
#if os(iOS) || os(macOS) || os(visionOS)
        observedChatView
            .modifier(ChatImageDropModifier(
                imageImportDriver: imageImportDriver,
                supportsImageInput: currentModelSupportsImageInput,
                viewModel: viewModel,
                errorCenter: errorCenter,
                focusInput: { isInputFocused = true }
            ))
#else
        observedChatView
#endif
    }

    var observedChatView: some View {
        presentationManagedChatView
            .modifier(ChatViewObservationModifier(
                viewModel: viewModel,
                branchRenderEpoch: $branchRenderEpoch,
                textFieldHeight: $textFieldHeight,
                inputOverflow: $inputOverflow,
                expectAssistantResponseHaptics: $expectAssistantResponseHaptics,
                didTriggerResponseStartHaptic: $didTriggerResponseStartHaptic,
                textHapticsEnabled: textHapticsEnabled,
                searchNavigationTarget: chatSessionsViewModel.searchNavigationTarget,
                visibleMessageCount: visibleMessages.count,
                isInitialContentReady: initialRenderCoordinator.isReady,
                triggerTextHaptic: triggerTextHaptic,
                onMessageContentUpdate: { update in
                    visibleMessageController.applyContentFingerprintUpdate(
                        messageID: update.messageID,
                        fingerprint: update.fingerprint
                    )
                },
                onVisibleMessagesNeedRefresh: { refreshVisibleMessages() },
                onSessionTransition: handleSessionTransition,
                onBranchTransition: handleBranchTransition,
                onSearchNavigationTargetChange: scheduleSearchNavigationIfNeeded(_:),
                onVisibleMessageCountChange: handleVisibleMessageCountChange,
                onInitialContentReady: handleInitialContentReady
            ))
    }

    var presentationManagedChatView: some View {
        lifecycleManagedChatView
            .modifier(ChatViewPresentationModifier(
                viewModel: viewModel,
                showFullScreenComposer: $showFullScreenComposer,
                showSystemCameraCapture: $imageImportDriver.showSystemCameraCapture,
                textSelectionSheetItem: $textSelectionSheetItem,
                showPhotoPicker: $imageImportDriver.showPhotoPicker,
                pickedPhotoItems: $imageImportDriver.pickedPhotoItems,
                showFileImporter: $imageImportDriver.showFileImporter,
                pendingPreviewFileURL: $imageImportDriver.pendingPreviewFileURL,
                activeAlert: $activeAlert,
                remainingPendingImageAttachmentSlots: imageImportDriver.remainingSlots(for: viewModel),
                onFullScreenComposerDismiss: { isInputFocused = true },
                onCapturedPhoto: { data, mimeType in
                    imageImportDriver.importCapturedPhotoData(
                        data,
                        mimeType: mimeType,
                        viewModel: viewModel,
                        errorCenter: errorCenter,
                        focusInput: { isInputFocused = true }
                    )
                },
                onCameraFailure: {
                    imageImportDriver.presentCameraCaptureFailureNotice(errorCenter: errorCenter)
                },
                onSelectedImageFiles: { result in
                    imageImportDriver.importSelectedImageFiles(
                        result,
                        viewModel: viewModel,
                        errorCenter: errorCenter,
                        focusInput: { isInputFocused = true }
                    )
                },
                onPickedPhotoItemsChanged: { items in
                    imageImportDriver.importPickedPhotoItems(
                        items,
                        viewModel: viewModel,
                        errorCenter: errorCenter,
                        focusInput: { isInputFocused = true }
                    )
                },
                onContinueVoiceInterrupt: {
                    sendCoordinator.interruptAllActivitiesForVoiceModeStart()
                    sendCoordinator.startRealtimeVoiceOverlay()
                },
                onContinueUnsupportedImageSend: {
                    sendCoordinator.performSend(ignoringUnsupportedImageInputs: true)
                },
                onContinueUnsupportedImageBranchRestart: { confirmation in
                    handleBranchRestartResult(
                        viewModel.continueBranchRestart(confirmation.intent)
                    )
                    triggerTextHaptic(.lightTap)
                },
                onEditUnsupportedImageBranchRestart: { userMessageID in
                    if viewModel.beginEditUserMessage(id: userMessageID) {
                        isInputFocused = true
                    }
                },
                onEditUnsupportedQueuedDraft: { draftID in
                    viewModel.editQueuedDraft(id: draftID)
                    isInputFocused = true
                },
                onContinueUnsupportedQueuedDraftTextOnly: { draftID in
                    sendCoordinator.sendQueuedDraftImmediately(draftID, ignoringUnsupportedImageInputs: true)
                },
                onDeleteUnsupportedQueuedDraft: { draftID in
                    viewModel.removeQueuedDraft(id: draftID)
                },
                onNothingToSendAfterDroppingImages: sendCoordinator.publishNothingToSendAfterDroppingImages
            ))
    }

    var lifecycleManagedChatView: some View {
        layoutDecoratedChatView
            .modifier(ChatViewLifecycleModifier(
                editingBannerHeight: $editingBannerHeight,
                onAppear: handleChatViewAppear,
                onDisappear: handleChatViewDisappear
            ))
    }

    var layoutDecoratedChatView: some View {
        mainChatLayout
            .modifier(ChatViewChromeModifier(
                layoutMetrics: layoutMetrics,
                availableMessageWidth: availableMessageWidth,
                showScrollToBottomButton: scrollState.showScrollToBottomButton,
                notices: errorCenter.notices,
                onDismissNotice: errorCenter.dismiss(_:),
                composer: { floatingInputPanel },
                scrollToBottomButton: { scrollToBottomButton },
                shadowShelf: {
                    ChatComposerShadowShelf()
                }
            ))
    }

    var mainChatLayout: some View {
        ChatConversationLayout(
            audioManager: audioManager,
            navigationTitle: viewModel.chatSession.title,
            isInitialContentReady: initialRenderCoordinator.isReady,
            isVoiceOverlayPresented: voiceOverlayVM.isPresented,
            shouldDisplayAudioPlayer: shouldDisplayAudioPlayer,
            messageList: { chatMessageList(scrollTargetsEnabled: true) },
            hydrationMask: { hydrationMaskView },
            onContentHeightChange: updateContentHeightIfNeeded(_:),
            onViewportHeightChange: updateViewportHeightIfNeeded(_:),
            onBottomAnchorChange: updateBottomAnchorIfNeeded(_:),
            onDismissKeyboard: { isInputFocused = false },
            onWidthChange: updateAvailableMessageWidth(_:),
            onScrollProxyReady: handleScrollProxyReady(_:availableWidth:)
        )
        .environment(\.chatInitialRenderCoordinator, initialRenderCoordinator)
        .task(id: isHydratingSession) {
            let presentationGeneration = initialRenderCoordinator.generation
            guard !isHydratingSession else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            initialRenderCoordinator.finishCollecting(
                generation: presentationGeneration
            )
        }
    }

    var floatingInputPanel: some View {
        ChatComposerPanelBinder(
            viewModel: viewModel,
            imageImportDriver: imageImportDriver,
            textFieldHeight: $textFieldHeight,
            activeAlert: $activeAlert,
            inputFocused: $isInputFocused,
            inputOverflow: inputOverflow,
            layoutMetrics: layoutMetrics,
            supportsImageInput: currentModelSupportsImageInput,
            canSendDraft: canSendDraft,
            thinkingCapability: currentModelThinkingCapability,
            thinkingOption: currentThinkingOption,
            errorCenter: errorCenter,
            onOpenFullScreenComposer: { showFullScreenComposer = true },
            onOverflowChange: handleOverflowChange,
            onFocusInput: { isInputFocused = true },
            onBlurInput: { isInputFocused = false },
            onSendDraft: { sendCoordinator.sendQueuedDraftImmediately($0) },
            onQueueDraft: { sendCoordinator.queueCurrentDraftIfPossible() },
            onCancelGeneration: {
                expectAssistantResponseHaptics = false
                didTriggerResponseStartHaptic = false
                viewModel.cancelCurrentRequest()
                triggerTextHaptic(.warning)
            },
            onSend: sendCoordinator.sendIfPossible,
            onStartRealtimeVoice: sendCoordinator.openRealtimeVoiceOverlay
        )
    }

    var scrollToBottomButton: some View {
        ChatScrollToBottomButton(size: layoutMetrics.scrollButtonSize) {
            scrollToBottom()
        }
    }

    func chatMessageList(scrollTargetsEnabled: Bool) -> some View {
        ChatMessageList(
            visibleMessages: visibleMessages,
            fingerprintCache: visibleMessageController.fingerprintCache,
            branchRenderEpoch: branchRenderEpoch,
            isLoading: viewModel.isLoading,
            isPriming: viewModel.isPriming,
            isToolContinuationLoading: viewModel.isToolContinuationLoading,
            isRetrying: viewModel.isRetrying,
            retryAttempt: viewModel.retryAttempt,
            retryLastError: viewModel.retryLastError,
            messageToolActivities: viewModel.messageToolActivities,
            messageToolActivityPlacements: viewModel.messageToolActivityPlacements,
            branchControlsEnabled: !(viewModel.isLoading || viewModel.isPriming || viewModel.isToolContinuationLoading || viewModel.isEditing),
            developerModeEnabled: settingsManager.developerModeEnabled,
            activeSearchHighlightTargetID: scrollInteractionState.activeSearchHighlightTargetID,
            availableMessageWidth: availableMessageWidth,
            messageListBottomInset: layoutMetrics.messageListBottomInset,
            horizontalPadding: layoutMetrics.messageListHorizontalPadding,
            topPadding: layoutMetrics.messageListTopPadding,
            scrollTargetsEnabled: scrollTargetsEnabled,
            isInitialContentReady: initialRenderCoordinator.isReady,
            searchHighlightQuery: searchHighlightQuery(for:),
            onSelectText: showSelectTextSheet(with:),
            onRegenerate: { message in
                handleBranchRestartResult(viewModel.regenerateSystemMessage(message))
                triggerTextHaptic(.lightTap)
            },
            onEditUserMessage: { message in
                viewModel.beginEditUserMessage(message)
                isInputFocused = true
            },
            onSwitchVersion: viewModel.switchToMessageVersion,
            onRetry: { message in
                handleBranchRestartResult(viewModel.retry(afterErrorMessage: message))
                triggerTextHaptic(.lightTap)
            },
            onAuthorizeTool: { requestID, allowed in
                viewModel.resolveToolAuthorization(requestID: requestID, allowed: allowed)
            }
        )
    }

    func handleOverflowChange(_ overflow: Bool) {
        let shouldShowEditorExpander = overflow
        if shouldShowEditorExpander != inputOverflow {
            DispatchQueue.main.async {
                inputOverflow = shouldShowEditorExpander
            }
        }
    }

    func handleBranchRestartResult(_ result: ChatBranchRestartRequestResult) {
        didTriggerResponseStartHaptic = false
        switch result {
        case .started:
            expectAssistantResponseHaptics = true
        case .requiresUnsupportedImageConfirmation(let confirmation):
            expectAssistantResponseHaptics = false
            activeAlert = .unsupportedImageBranchRestart(confirmation)
        case .unavailable:
            expectAssistantResponseHaptics = false
        }
    }

    func showSelectTextSheet(with text: String) {
        let selectionText = text
        guard !selectionText.isEmpty else { return }

        // Presenting a sheet directly from a context menu action is unreliable; schedule for next run loop.
        DispatchQueue.main.async {
            textSelectionSheetItem = TextSelectionSheetItem(text: selectionText)
        }
    }

    var hydrationMaskView: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
