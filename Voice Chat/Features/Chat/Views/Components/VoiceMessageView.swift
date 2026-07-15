//
//  VoiceMessageView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI
#if os(iOS) || os(macOS) || os(visionOS)
import QuickLook
#endif
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct VoiceMessageView: View {
    let message: ChatMessage
    @EnvironmentObject var audioManager: GlobalAudioManager
    @State private var messagePreviewFileURL: URL?
    @State private var isShowingMessageDetails = false
    @State private var isShowingCopyFeedback = false
    @State private var copyFeedbackToken = 0

    let isStreamingAssistant: Bool
    let showActionButtons: Bool
    let branchControlsEnabled: Bool
    let developerModeEnabled: Bool
    let maxBubbleWidth: CGFloat?
    let contentFingerprint: ContentFingerprint
    let inlineErrorMessage: ChatMessage?
    let inlineLoading: Bool
    let inlineRetryAttempt: Int?
    let inlineRetryLastError: String?
    let toolActivities: [ChatToolActivity]
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let searchHighlightQuery: String?
    let onSelectText: (String) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onEditUserMessage: (ChatMessage) -> Void
    let onSwitchVersion: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void
    let onAuthorizeTool: (String, Bool) -> Void

    private let thinkPreviewLines: Int = 6
    private let thinkFontSize: CGFloat = 14

    init(
        message: ChatMessage,
        isStreamingAssistant: Bool = false,
        showActionButtons: Bool,
        branchControlsEnabled: Bool,
        developerModeEnabled: Bool,
        maxBubbleWidth: CGFloat? = nil,
        contentFingerprint: ContentFingerprint,
        inlineErrorMessage: ChatMessage? = nil,
        inlineLoading: Bool = false,
        inlineRetryAttempt: Int? = nil,
        inlineRetryLastError: String? = nil,
        toolActivities: [ChatToolActivity] = [],
        toolActivityPlacements: [ChatToolActivityPlacement] = [],
        searchHighlightQuery: String? = nil,
        onSelectText: @escaping (String) -> Void,
        onRegenerate: @escaping (ChatMessage) -> Void,
        onEditUserMessage: @escaping (ChatMessage) -> Void,
        onSwitchVersion: @escaping (ChatMessage) -> Void,
        onRetry: @escaping (ChatMessage) -> Void,
        onAuthorizeTool: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        self.message = message
        self.isStreamingAssistant = isStreamingAssistant
        self.showActionButtons = showActionButtons
        self.branchControlsEnabled = branchControlsEnabled
        self.developerModeEnabled = developerModeEnabled
        self.maxBubbleWidth = maxBubbleWidth
        self.contentFingerprint = contentFingerprint
        self.inlineErrorMessage = inlineErrorMessage
        self.inlineLoading = inlineLoading
        self.inlineRetryAttempt = inlineRetryAttempt
        self.inlineRetryLastError = inlineRetryLastError
        self.toolActivities = toolActivities
        self.toolActivityPlacements = toolActivityPlacements
        self.searchHighlightQuery = searchHighlightQuery
        self.onSelectText = onSelectText
        self.onRegenerate = onRegenerate
        self.onEditUserMessage = onEditUserMessage
        self.onSwitchVersion = onSwitchVersion
        self.onRetry = onRetry
        self.onAuthorizeTool = onAuthorizeTool
    }

    @ViewBuilder
    var body: some View {
        if message.content.hasPrefix("!error:") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ErrorBubbleView(text: String(message.content.dropFirst("!error:".count)).trimmingCharacters(in: .whitespacesAndNewlines)) {
                        onRetry(message)
                    }
                    .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                messageFooter(showActionControls: false, isUserMessage: false)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        } else {
            let userAttachments = message.imageAttachments
            let systemTextBubble = SystemTextBubble(
                message: message,
                thinkPreviewLines: thinkPreviewLines,
                thinkFontSize: thinkFontSize,
                developerModeEnabled: developerModeEnabled,
                maxBubbleWidth: maxBubbleWidth,
                contentFingerprint: contentFingerprint,
                toolActivityPlacements: toolActivityPlacements,
                searchHighlightQuery: searchHighlightQuery,
                isStreamingResponse: isStreamingAssistant,
                onAuthorizeTool: onAuthorizeTool
            )

            HStack(alignment: .top) {
                if message.isUser { Spacer(minLength: 40) } else { Spacer(minLength: 0) }

                if message.isUser {
                    VStack(alignment: .trailing, spacing: 4) {
                        UserTextBubble(
                            text: message.content,
                            attachments: userAttachments,
                            maxBubbleWidth: maxBubbleWidth,
                            searchHighlightQuery: searchHighlightQuery,
                            onPreviewImage: { attachment in
                                presentMessageAttachmentPreview(attachment)
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        messageFooter(showActionControls: false, isUserMessage: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        systemTextBubble
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        inlineErrorBubble
                        inlineStatusBubble
                        messageFooter(showActionControls: shouldShowAssistantActionControls, isUserMessage: false)
                    }
                    .animation(
                        .spring(response: 0.35, dampingFraction: 0.85),
                        value: inlineErrorMessage?.id
                    )
                    .animation(
                        .spring(response: 0.35, dampingFraction: 0.85),
                        value: inlineStatusAnimationKey
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .modifier(UserContextMenuModifier(
                isUser: message.isUser,
                message: message,
                developerModeEnabled: developerModeEnabled,
                toolActivities: toolActivities,
                toolActivityPlacements: toolActivityPlacements,
                onSelectText: onSelectText,
                onEditUserMessage: onEditUserMessage,
                copyToClipboard: copyToClipboard
            ))
            .task(id: copyFeedbackToken) {
                guard copyFeedbackToken > 0 else { return }
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isShowingCopyFeedback = false
                    }
                }
            }
            .onDisappear {
                isShowingCopyFeedback = false
                copyFeedbackToken = 0
            }
            .sheet(isPresented: $isShowingMessageDetails) {
                MessageDetailsView(
                    message: message,
                    toolActivities: toolActivities,
                    toolActivityPlacements: toolActivityPlacements,
                    developerModeEnabled: developerModeEnabled
                )
            }
            .onChange(of: developerModeEnabled) { _, isEnabled in
                if !isEnabled {
                    isShowingMessageDetails = false
                }
            }
#if os(iOS) || os(macOS) || os(visionOS)
            .quickLookPreview($messagePreviewFileURL)
            .onChange(of: messagePreviewFileURL) { oldValue, newValue in
                guard oldValue != newValue else { return }
                ChatImageQuickLookSupport.cleanupTemporaryPreviewURL(oldValue)
            }
            .onDisappear {
                ChatImageQuickLookSupport.cleanupTemporaryPreviewURL(messagePreviewFileURL)
                messagePreviewFileURL = nil
            }
#endif
        }
    }

    private var shouldShowAssistantActionControls: Bool {
        guard showActionButtons, !message.isUser, !message.content.hasPrefix("!error:") else {
            return false
        }
        let parts = message.content.extractThinkParts()
        let hasReasoning = message.hasAssistantSegments ? message.assistantReasoningText != nil : parts.think != nil
        let bodyText = message.hasAssistantSegments ? message.assistantText : parts.body
        return hasReasoning ||
            !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !toolActivityPlacements.isEmpty ||
            !toolActivities.isEmpty
    }

    @ViewBuilder
    private var inlineErrorBubble: some View {
        if let inlineErrorMessage {
            HStack {
                ErrorBubbleView(text: errorText(for: inlineErrorMessage)) {
                    onRetry(inlineErrorMessage)
                }
                .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func errorText(for message: ChatMessage) -> String {
        String(message.content.dropFirst("!error:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var inlineStatusBubble: some View {
        if let inlineRetryAttempt {
            HStack {
                AssistantRetryingBubbleContent(
                    attempt: inlineRetryAttempt,
                    lastError: inlineRetryLastError
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if inlineLoading {
            HStack {
                AssistantLoadingBubbleContent()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var inlineStatusAnimationKey: String {
        if let inlineRetryAttempt {
            return "retry-\(inlineRetryAttempt)-\(inlineRetryLastError ?? "")"
        }
        return inlineLoading ? "loading" : "none"
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    #if os(iOS) || os(macOS) || os(visionOS)
    private func presentMessageAttachmentPreview(_ attachment: ChatImageAttachment) {
        let previous = messagePreviewFileURL
        messagePreviewFileURL = ChatImageQuickLookSupport.prepareTemporaryPreviewURL(for: attachment)
        if previous != messagePreviewFileURL {
            ChatImageQuickLookSupport.cleanupTemporaryPreviewURL(previous)
        }
    }
    #else
    private func presentMessageAttachmentPreview(_ attachment: ChatImageAttachment) {
        _ = attachment
    }
    #endif

    private func versionsForCurrentMessage() -> [ChatMessage] {
        let candidates: [ChatMessage]
        if let parent = message.parentMessage {
            let direct = parent.childMessages.filter { $0.isUser == message.isUser }
            if !direct.isEmpty {
                candidates = direct
            } else if let session = message.session {
                let parentID = parent.id
                candidates = session.messages.filter { candidate in
                    guard candidate.isUser == message.isUser else { return false }
                    return candidate.parentMessage?.id == parentID
                }
            } else {
                candidates = [message]
            }
        } else if let session = message.session {
            candidates = session.messages.filter { $0.parentMessage == nil && $0.isUser == message.isUser }
        } else {
            candidates = [message]
        }

        var versions = candidates
        if !versions.contains(where: { $0.id == message.id }) {
            versions.append(message)
        }

        return versions.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    @ViewBuilder
    private func messageFooter(showActionControls: Bool, isUserMessage: Bool) -> some View {
        let alignment: Alignment = isUserMessage ? .trailing : .leading
        let maxWidth = isUserMessage
            ? contentMaxWidthForUser(availableWidth: maxBubbleWidth)
            : contentMaxWidthForAssistant(availableWidth: maxBubbleWidth)
        if showActionControls || hasMessageBranchControls {
            HStack(spacing: 10) {
                if showActionControls {
                    assistantActionControls
                }
                branchControls
            }
            .frame(maxWidth: maxWidth, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: isUserMessage ? .trailing : .center)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var assistantActionControls: some View {
        HStack(spacing: 6) {
            Button { handleCopy() } label: {
                Image(systemName: isShowingCopyFeedback ? "checkmark" : "doc.on.doc")
                    .messageControlIconStyle()
                    .frame(minWidth: 18, minHeight: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isShowingCopyFeedback ? Color.green : .secondary)
            .accessibilityLabel(isShowingCopyFeedback ? Text("Copied") : Text("Copy"))

            Button { onRegenerate(message) } label: {
                Image(systemName: "arrow.clockwise")
                    .messageControlIconStyle()
                    .accessibilityLabel("Regenerate")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                audioManager.startProcessing(text: assistantBodyTextForActions)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .messageControlIconStyle()
                    .accessibilityLabel("Read Aloud")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if developerModeEnabled {
                Button { isShowingMessageDetails = true } label: {
                    Image(systemName: "info.circle")
                        .messageControlIconStyle()
                        .accessibilityLabel("Details")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func handleCopy() {
        copyToClipboard(assistantBodyTextForActions)
        withAnimation(.easeInOut(duration: 0.18)) {
            isShowingCopyFeedback = true
        }
        copyFeedbackToken += 1
    }

    private var assistantBodyTextForActions: String {
        message.hasAssistantSegments ? message.assistantText : message.content.extractThinkParts().body
    }

    private var hasMessageBranchControls: Bool {
        let versions = versionsForCurrentMessage()
        return versions.count > 1 && versions.contains(where: { $0.id == message.id })
    }

    @ViewBuilder
    private var branchControls: some View {
        let versions = versionsForCurrentMessage()
        if versions.count > 1,
           let idx = versions.firstIndex(where: { $0.id == message.id }) {
            MessageBranchControls(
                currentIndex: idx + 1,
                totalCount: versions.count,
                isEnabled: branchControlsEnabled,
                canGoPrevious: idx > 0,
                canGoNext: idx < (versions.count - 1),
                onPrevious: {
                    guard idx > 0 else { return }
                    onSwitchVersion(versions[idx - 1])
                },
                onNext: {
                    guard idx < (versions.count - 1) else { return }
                    onSwitchVersion(versions[idx + 1])
                }
            )
        }
    }
}

private extension Image {
    func messageControlIconStyle() -> some View {
        self
            #if os(macOS)
            .font(.system(size: 12, weight: .semibold))
            #else
            .font(.system(size: 16, weight: .semibold))
            #endif
            .padding(2)
    }
}
