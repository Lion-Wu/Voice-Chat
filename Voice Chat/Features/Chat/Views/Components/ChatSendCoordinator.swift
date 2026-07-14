#if os(iOS) || os(macOS) || os(visionOS)

import Foundation

@MainActor
struct ChatSendCoordinator {
    let viewModel: ChatViewModel
    let chatSessionsViewModel: ChatSessionsViewModel
    let audioManager: GlobalAudioManager
    let errorCenter: AppErrorCenter
    let voiceOverlayVM: VoiceChatOverlayViewModel
    let imageImportDriver: ChatImageAttachmentImportDriver
    let focusInput: () -> Void
    let setActiveAlert: (ChatAlert) -> Void
    let setResponseHapticState: (_ expectsAssistantResponse: Bool, _ didTriggerResponseStart: Bool) -> Void
    let requestScrollToBottomAfterSend: () -> Void
    let cancelScrollToBottomAfterSend: () -> Void
    let triggerTextHaptic: (AppHapticEvent) -> Void

    var canSendDraft: Bool {
        !trimmedUserMessage.isEmpty || viewModel.hasPendingImageAttachments
    }

    var hasOtherActivityForVoiceModeStart: Bool {
        let hasText = chatSessionsViewModel.hasActiveTextRequests
        let hasVoice = audioManager.audioPlaybackSnapshot.hasVoiceWork
        return hasText || hasVoice
    }

    @discardableResult
    func sendIfPossible() -> Bool {
        guard canSendDraft else { return false }
        if viewModel.isLoading || viewModel.isPriming || viewModel.isToolContinuationLoading {
            return queueCurrentDraftIfPossible()
        }
        if viewModel.shouldWarnAboutUnsupportedImageInputBeforeSending() {
            setActiveAlert(.unsupportedImageSend)
            return false
        }
        return performSend(ignoringUnsupportedImageInputs: false)
    }

    @discardableResult
    func queueCurrentDraftIfPossible() -> Bool {
        guard canSendDraft else { return false }
        guard viewModel.enqueueCurrentDraft() else { return false }
        triggerTextHaptic(.lightTap)
        return true
    }

    @discardableResult
    func performSend(ignoringUnsupportedImageInputs: Bool) -> Bool {
        beginAssistantResponseHaptics()
        requestScrollToBottomAfterSend()
        guard viewModel.sendMessage(ignoringUnsupportedImageInputs: ignoringUnsupportedImageInputs) else {
            cancelAssistantResponseHaptics()
            cancelScrollToBottomAfterSend()
            return false
        }
        triggerTextHaptic(.lightTap)
        return true
    }

    func publishNothingToSendAfterDroppingImages() {
        errorCenter.publish(
            title: NSLocalizedString("Nothing to send", comment: "Shown when sending is skipped because no text remains after removing unsupported image inputs"),
            message: NSLocalizedString("All selected images were ignored because this model only accepts text input.", comment: "Shown when selected images are dropped for a text-only model"),
            category: .textModel
        )
    }

    @discardableResult
    func performRealtimeVoiceSend(_ text: String, imageAttachments: [ChatImageAttachment]) -> Bool {
        beginAssistantResponseHaptics()
        requestScrollToBottomAfterSend()
        guard viewModel.sendRealtimeVoiceMessage(text, imageAttachments: imageAttachments) else {
            restoreRealtimeVoiceDraft(text, imageAttachments: imageAttachments)
            cancelAssistantResponseHaptics()
            cancelScrollToBottomAfterSend()
            if viewModel.isLoading || viewModel.isPriming || viewModel.isToolContinuationLoading {
                _ = queueCurrentDraftIfPossible()
            } else if viewModel.shouldWarnAboutUnsupportedImageInputBeforeSending() {
                setActiveAlert(.unsupportedImageSend)
            }
            return false
        }
        triggerTextHaptic(.lightTap)
        return true
    }

    @discardableResult
    func sendQueuedDraftImmediately(_ draftID: UUID, ignoringUnsupportedImageInputs: Bool = false) -> Bool {
        if !ignoringUnsupportedImageInputs,
           let draft = viewModel.queuedDraft(id: draftID),
           viewModel.shouldWarnAboutUnsupportedImageInput(for: draft) {
            viewModel.requestUnsupportedImageConfirmationForQueuedDraft(id: draftID)
            return false
        }
        beginAssistantResponseHaptics()
        requestScrollToBottomAfterSend()
        guard viewModel.sendQueuedDraftNow(
            id: draftID,
            ignoringUnsupportedImageInputs: ignoringUnsupportedImageInputs
        ) else {
            cancelAssistantResponseHaptics()
            cancelScrollToBottomAfterSend()
            return false
        }
        triggerTextHaptic(.lightTap)
        return true
    }

    func interruptAllActivitiesForVoiceModeStart() {
        chatSessionsViewModel.cancelAllActiveTextRequests(autostartQueuedDrafts: false)
        if audioManager.audioPlaybackSnapshot.hasVoiceWork {
            audioManager.closeAudioPlayer()
        }
    }

    func openRealtimeVoiceOverlay() {
        guard !voiceOverlayVM.isPresented else { return }
        if hasOtherActivityForVoiceModeStart {
            setActiveAlert(.startVoiceModeInterrupt)
            return
        }
        startRealtimeVoiceOverlay()
    }

    func startRealtimeVoiceOverlay() {
        guard !voiceOverlayVM.isPresented else { return }
        AppHaptics.trigger(.selection)
        cancelAssistantResponseHaptics()
        voiceOverlayVM.presentSession(chatSession: viewModel) { text, imageAttachments in
            _ = performRealtimeVoiceSend(text, imageAttachments: imageAttachments)
        }
    }

    private var trimmedUserMessage: String {
        viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restoreRealtimeVoiceDraft(_ text: String, imageAttachments: [ChatImageAttachment]) {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.userMessage = text
        }
        imageImportDriver.appendPendingImageAttachments(
            imageAttachments,
            viewModel: viewModel,
            errorCenter: errorCenter,
            focusInput: focusInput
        )
    }

    private func beginAssistantResponseHaptics() {
        setResponseHapticState(true, false)
    }

    private func cancelAssistantResponseHaptics() {
        setResponseHapticState(false, false)
    }
}

#endif
