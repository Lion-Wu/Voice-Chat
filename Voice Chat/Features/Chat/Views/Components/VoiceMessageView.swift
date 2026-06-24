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

    let isStreamingAssistant: Bool
    let showActionButtons: Bool
    let branchControlsEnabled: Bool
    let developerModeEnabled: Bool
    let maxBubbleWidth: CGFloat?
    let contentFingerprint: ContentFingerprint
    let toolActivities: [ChatToolActivity]
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let searchHighlightQuery: String?
    let onSelectText: (String) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onEditUserMessage: (ChatMessage) -> Void
    let onSwitchVersion: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void

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
        toolActivities: [ChatToolActivity] = [],
        toolActivityPlacements: [ChatToolActivityPlacement] = [],
        searchHighlightQuery: String? = nil,
        onSelectText: @escaping (String) -> Void,
        onRegenerate: @escaping (ChatMessage) -> Void,
        onEditUserMessage: @escaping (ChatMessage) -> Void,
        onSwitchVersion: @escaping (ChatMessage) -> Void,
        onRetry: @escaping (ChatMessage) -> Void
    ) {
        self.message = message
        self.isStreamingAssistant = isStreamingAssistant
        self.showActionButtons = showActionButtons
        self.branchControlsEnabled = branchControlsEnabled
        self.developerModeEnabled = developerModeEnabled
        self.maxBubbleWidth = maxBubbleWidth
        self.contentFingerprint = contentFingerprint
        self.toolActivities = toolActivities
        self.toolActivityPlacements = toolActivityPlacements
        self.searchHighlightQuery = searchHighlightQuery
        self.onSelectText = onSelectText
        self.onRegenerate = onRegenerate
        self.onEditUserMessage = onEditUserMessage
        self.onSwitchVersion = onSwitchVersion
        self.onRetry = onRetry
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

                systemBranchControls
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        } else {
            let userAttachments = message.imageAttachments
            let systemTextBubble = SystemTextBubble(
                message: message,
                thinkPreviewLines: thinkPreviewLines,
                thinkFontSize: thinkFontSize,
                showActionButtons: showActionButtons,
                developerModeEnabled: developerModeEnabled,
                maxBubbleWidth: maxBubbleWidth,
                contentFingerprint: contentFingerprint,
                toolActivities: toolActivities,
                toolActivityPlacements: toolActivityPlacements,
                searchHighlightQuery: searchHighlightQuery,
                isStreamingResponse: isStreamingAssistant,
                onCopy: { copyToClipboard(message.content.extractThinkParts().body) },
                onRegenerate: { onRegenerate(message) },
                onReadAloud: {
                    audioManager.startProcessing(text: message.content.extractThinkParts().body)
                }
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
                        userBranchControls
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        systemTextBubble
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        systemBranchControls
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .modifier(UserContextMenuModifier(
                isUser: message.isUser,
                message: message,
                onSelectText: onSelectText,
                onEditUserMessage: onEditUserMessage,
                copyToClipboard: copyToClipboard
            ))
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
    private var userBranchControls: some View {
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
            .frame(maxWidth: contentMaxWidthForUser(availableWidth: maxBubbleWidth), alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var systemBranchControls: some View {
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
            .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
