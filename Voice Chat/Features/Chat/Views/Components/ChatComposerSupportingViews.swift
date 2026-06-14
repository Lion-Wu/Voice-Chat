//
//  ChatComposerSupportingViews.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.13.
//

import SwiftUI

@MainActor
struct ChatComposerPanel: View {
    @Binding var userMessage: String
    @Binding var textFieldHeight: CGFloat
    let inputFocused: FocusState<Bool>.Binding
    let inputOverflow: Bool
    let hasSupportingContent: Bool
    let supportsImageInput: Bool
    let isEditingComposerDraft: Bool
    let isEditing: Bool
    let isLoading: Bool
    let isPriming: Bool
    let canSendDraft: Bool
    let queuedDrafts: [QueuedChatDraft]
    let pendingAttachments: [ChatImageAttachment]
    let thinkingCapability: ModelThinkingCapability?
    let thinkingOption: ModelThinkingOption?
    let remainingAttachmentSlots: Int
    let composerOuterVerticalPadding: CGFloat
    let composerPanelHorizontalPadding: CGFloat
    let composerBarCornerRadius: CGFloat
    let composerSupportSectionSpacing: CGFloat
    let composerSupportTopPadding: CGFloat
    let composerSupportBottomPadding: CGFloat
    let composerSupportHorizontalPadding: CGFloat
    let composerAttachmentButtonDiameter: CGFloat
    let composerAttachmentGlyphSize: CGFloat
    let composerDefaultMainBarHeight: CGFloat
    let queuedDraftRowHeight: CGFloat
    let queuedDraftHeight: CGFloat
    let composerAccessoryTapSize: CGFloat
    let thinkingControlHeight: CGFloat
    let floatingInputButtonHeight: CGFloat
    let composerDefaultTrailingButtonTrackHeight: CGFloat
    let onOpenFullScreenComposer: () -> Void
    let onOverflowChange: (Bool) -> Void
    let onPasteImages: ([(data: Data, mimeType: String?)]) -> Void
    let onAttachmentLimitReached: @MainActor () -> Void
    let onTakePhoto: @MainActor () -> Void
    let onChoosePhotos: @MainActor () -> Void
    let onChooseFiles: @MainActor () -> Void
    let onMoveDrafts: (IndexSet, Int) -> Void
    let onDeleteDraft: (UUID) -> Void
    let onEditDraft: (UUID) -> Void
    let onSendDraft: (UUID) -> Void
    let onPreviewAttachment: (ChatImageAttachment) -> Void
    let onRemoveAttachment: (ChatImageAttachment) -> Void
    let onSelectThinkingOption: (ModelThinkingOption) -> Void
    let onToggleThinking: () -> Void
    let onCancelEditing: () -> Void
    let onQueueDraft: () -> Void
    let onCancelGeneration: () -> Void
    let onSend: () -> Void
    let onStartRealtimeVoice: () -> Void

    var body: some View {
        AppLiquidGlassContainer(spacing: InputMetrics.composerRowSpacing) {
            HStack(alignment: .bottom, spacing: InputMetrics.composerRowSpacing) {
                if supportsImageInput {
                    attachmentButton
                }

                inputBar
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.18), value: isEditing)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if hasSupportingContent {
                supportingPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                Divider()
                    .overlay(ChatTheme.separator.opacity(0.5))
                    .padding(.horizontal, 12)
            }

            inputRow
                .padding(.vertical, composerOuterVerticalPadding)
                .padding(.leading, composerPanelHorizontalPadding)
                .padding(.trailing, 10)
        }
        .appChromedContainer(
            cornerRadius: composerBarCornerRadius,
            shadowOpacity: 0.28
        )
    }

    private var inputRow: some View {
        HStack(alignment: .center, spacing: InputMetrics.composerRowSpacing) {
            AutoSizingTextEditor(
                text: $userMessage,
                height: $textFieldHeight,
                placeholder: NSLocalizedString("Type your message...", comment: "Chat composer placeholder"),
                maxLines: platformMaxLines(),
                allowsImagePasting: supportsImageInput,
                maxPastedImages: remainingAttachmentSlots,
                onOverflowChange: onOverflowChange,
                onPasteImages: onPasteImages
            )
            .focused(inputFocused)
            .frame(maxWidth: .infinity)
            .frame(height: textFieldHeight)
            .padding(.vertical, InputMetrics.composerOuterV)
            .padding(.leading, InputMetrics.composerOuterLeading)
            .padding(.trailing, 6)
            .overlay(alignment: .topTrailing) {
                #if os(iOS) || os(tvOS)
                if inputOverflow {
                    Button(action: onOpenFullScreenComposer) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                    .padding(.trailing, 8)
                    .accessibilityLabel("Open full screen editor")
                }
                #endif
            }
            .frame(maxWidth: .infinity)

            trailingButton
        }
    }

    @ViewBuilder
    private var supportingPanel: some View {
        VStack(spacing: composerSupportSectionSpacing) {
            if isEditingComposerDraft {
                ChatEditingAccessory(
                    accessoryTapSize: composerAccessoryTapSize,
                    onCancel: onCancelEditing
                )
            }

            if !queuedDrafts.isEmpty {
                ChatQueuedDraftStrip(
                    drafts: queuedDrafts,
                    rowHeight: queuedDraftRowHeight,
                    stripHeight: queuedDraftHeight,
                    accessoryTapSize: composerAccessoryTapSize,
                    onMove: onMoveDrafts,
                    onDelete: onDeleteDraft,
                    onEdit: onEditDraft,
                    onSend: onSendDraft
                )
            }

            if let thinkingCapability, thinkingCapability.isConfigurable {
                ChatThinkingControl(
                    capability: thinkingCapability,
                    currentOption: thinkingOption,
                    height: thinkingControlHeight,
                    onSelectOption: onSelectThinkingOption,
                    onToggle: onToggleThinking
                )
            }

            if !pendingAttachments.isEmpty {
                ChatImageAttachmentStrip(
                    attachments: pendingAttachments,
                    removable: true,
                    maxItemSize: 72,
                    onPreview: onPreviewAttachment,
                    onRemove: onRemoveAttachment
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, composerSupportTopPadding)
        .padding(.bottom, composerSupportBottomPadding)
        .padding(.horizontal, composerSupportHorizontalPadding)
    }

    @ViewBuilder
    private var attachmentButton: some View {
        #if os(iOS) || os(macOS) || os(visionOS)
        ChatComposerAttachmentButton(
            supportsImageInput: supportsImageInput,
            buttonDiameter: composerAttachmentButtonDiameter,
            glyphSize: composerAttachmentGlyphSize,
            defaultMainBarHeight: composerDefaultMainBarHeight,
            remainingSlots: remainingAttachmentSlots,
            onLimitReached: onAttachmentLimitReached,
            onTakePhoto: onTakePhoto,
            onChoosePhotos: onChoosePhotos,
            onChooseFiles: onChooseFiles
        )
        #endif
    }

    private var trailingButton: some View {
        ChatComposerTrailingButton(
            isLoading: isLoading,
            isPriming: isPriming,
            canSendDraft: canSendDraft,
            buttonHeight: floatingInputButtonHeight,
            trackHeight: composerDefaultTrailingButtonTrackHeight,
            onQueueDraft: onQueueDraft,
            onCancelGeneration: onCancelGeneration,
            onSend: onSend,
            onStartRealtimeVoice: onStartRealtimeVoice
        )
    }
}
