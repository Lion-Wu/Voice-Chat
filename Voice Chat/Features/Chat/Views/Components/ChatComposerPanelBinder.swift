//
//  ChatComposerPanelBinder.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

#if os(iOS) || os(macOS) || os(visionOS)
import SwiftUI

@MainActor
struct ChatComposerPanelBinder: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var imageImportDriver: ChatImageAttachmentImportDriver

    @Binding var textFieldHeight: CGFloat
    @Binding var activeAlert: ChatAlert?

    let inputFocused: FocusState<Bool>.Binding
    let inputOverflow: Bool
    let layoutMetrics: ChatComposerLayoutMetrics
    let supportsImageInput: Bool
    let canSendDraft: Bool
    let thinkingCapability: ModelThinkingCapability?
    let thinkingOption: ModelThinkingOption?
    let errorCenter: AppErrorCenter
    let onOpenFullScreenComposer: () -> Void
    let onOverflowChange: (Bool) -> Void
    let onFocusInput: () -> Void
    let onBlurInput: () -> Void
    let onSendDraft: (UUID) -> Bool
    let onQueueDraft: () -> Bool
    let onCancelGeneration: () -> Void
    let onSend: () -> Bool
    let onStartRealtimeVoice: () -> Void

    var body: some View {
        ChatComposerPanel(
            userMessage: $viewModel.userMessage,
            textFieldHeight: $textFieldHeight,
            inputFocused: inputFocused,
            inputOverflow: inputOverflow,
            hasSupportingContent: layoutMetrics.hasComposerSupportingContent,
            supportsImageInput: supportsImageInput,
            isEditingComposerDraft: viewModel.isEditingComposerDraft,
            isEditing: viewModel.isEditing,
            isLoading: viewModel.isLoading,
            isPriming: viewModel.isPriming,
            canSendDraft: canSendDraft,
            queuedDrafts: viewModel.queuedDrafts,
            pendingAttachments: viewModel.pendingImageAttachments,
            thinkingCapability: thinkingCapability,
            thinkingOption: thinkingOption,
            remainingAttachmentSlots: imageImportDriver.remainingSlots(for: viewModel),
            composerOuterVerticalPadding: layoutMetrics.composerOuterVerticalPadding,
            composerPanelHorizontalPadding: layoutMetrics.composerPanelHorizontalPadding,
            composerBarCornerRadius: layoutMetrics.composerBarCornerRadius,
            composerSupportSectionSpacing: layoutMetrics.composerSupportSectionSpacing,
            composerSupportTopPadding: layoutMetrics.composerSupportTopPadding,
            composerSupportBottomPadding: layoutMetrics.composerSupportBottomPadding,
            composerSupportHorizontalPadding: layoutMetrics.composerSupportHorizontalPadding,
            composerAttachmentButtonDiameter: layoutMetrics.composerAttachmentButtonDiameter,
            composerAttachmentGlyphSize: layoutMetrics.composerAttachmentGlyphSize,
            composerDefaultMainBarHeight: layoutMetrics.composerDefaultMainBarHeight,
            queuedDraftRowHeight: layoutMetrics.queuedDraftRowHeight,
            queuedDraftHeight: layoutMetrics.queuedDraftHeight,
            composerAccessoryTapSize: layoutMetrics.composerAccessoryTapSize,
            thinkingControlHeight: layoutMetrics.thinkingControlHeight,
            floatingInputButtonHeight: layoutMetrics.floatingInputButtonHeight,
            composerDefaultTrailingButtonTrackHeight: layoutMetrics.composerDefaultTrailingButtonTrackHeight,
            onOpenFullScreenComposer: onOpenFullScreenComposer,
            onOverflowChange: onOverflowChange,
            onPasteImages: importPastedImages(_:),
            onAttachmentLimitReached: {
                imageImportDriver.presentImageAttachmentLimitNotice(errorCenter: errorCenter)
            },
            onTakePhoto: {
                imageImportDriver.presentSystemCameraCapture(errorCenter: errorCenter)
            },
            onChoosePhotos: { imageImportDriver.showPhotoPicker = true },
            onChooseFiles: { imageImportDriver.showFileImporter = true },
            onMoveDrafts: viewModel.moveQueuedDrafts,
            onDeleteDraft: { activeAlert = .deleteQueuedDraft($0) },
            onEditDraft: editDraft(_:),
            onSendDraft: { _ = onSendDraft($0) },
            onPreviewAttachment: imageImportDriver.presentPendingAttachmentPreview(_:),
            onRemoveAttachment: { attachment in
                viewModel.removePendingImageAttachment(id: attachment.id)
            },
            onSelectThinkingOption: viewModel.setCurrentThinkingOption(_:),
            onToggleThinking: viewModel.toggleCurrentThinking,
            onCancelEditing: cancelEditing,
            onQueueDraft: { _ = onQueueDraft() },
            onCancelGeneration: onCancelGeneration,
            onSend: { _ = onSend() },
            onStartRealtimeVoice: onStartRealtimeVoice
        )
    }

    private func importPastedImages(_ payloads: [(data: Data, mimeType: String?)]) {
        imageImportDriver.importPastedImages(
            payloads,
            viewModel: viewModel,
            errorCenter: errorCenter,
            focusInput: onFocusInput
        )
    }

    private func editDraft(_ draftID: UUID) {
        viewModel.editQueuedDraft(id: draftID)
        onFocusInput()
    }

    private func cancelEditing() {
        viewModel.cancelEditing()
        onBlurInput()
    }
}
#endif
