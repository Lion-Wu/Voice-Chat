//
//  VoiceMessageView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

struct VoiceMessageView: View {
    @Bindable var message: ChatMessage
    @EnvironmentObject var audioManager: GlobalAudioManager

    let showActionButtons: Bool
    let branchControlsEnabled: Bool
    let contentFingerprint: ContentFingerprint
    let onSelectText: (String) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onEditUserMessage: (ChatMessage) -> Void
    let onSwitchVersion: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void

    private let thinkPreviewLines: Int = 6
    private let thinkFontSize: CGFloat = 14
    private let thinkFont: Font = .system(size: 14, design: .monospaced)

    @ViewBuilder
    var body: some View {
        if message.content.hasPrefix("!error:") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ErrorBubbleView(text: String(message.content.dropFirst("!error:".count)).trimmingCharacters(in: .whitespacesAndNewlines)) {
                        onRetry(message)
                    }
                    .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                systemBranchControls
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        } else {
            let systemTextBubble = SystemTextBubble(
            message: message,
            thinkPreviewLines: thinkPreviewLines,
            thinkFontSize: thinkFontSize,
            thinkFont: thinkFont,
            showActionButtons: showActionButtons,
            contentFingerprint: contentFingerprint,
            onCopy: { copyToClipboard(message.content.extractThinkParts().body) },
            onRegenerate: { onRegenerate(message) },
            onReadAloud: { audioManager.startProcessing(text: message.content.extractThinkParts().body) }
        )

            HStack(alignment: .top) {
                if message.isUser { Spacer(minLength: 40) } else { Spacer(minLength: 0) }

                if message.isUser {
                    VStack(alignment: .trailing, spacing: 4) {
                        UserTextBubble(text: message.content)
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
            .frame(maxWidth: contentMaxWidthForUser(), alignment: .trailing)
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
            .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// ContextMenu modifier for user messages only
struct UserContextMenuModifier: ViewModifier {
    let isUser: Bool
    let message: ChatMessage
    let onSelectText: (String) -> Void
    let onEditUserMessage: (ChatMessage) -> Void
    let copyToClipboard: (String) -> Void

    func body(content: Content) -> some View {
        if isUser {
            content.contextMenu(menuItems: {
                let parts = message.content.extractThinkParts()
                let bodyText = parts.body
                Button { copyToClipboard(bodyText) } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { onSelectText(bodyText) } label: { Label("Select Text", systemImage: "text.cursor") }
                Button { onEditUserMessage(message) } label: { Label("Edit Message", systemImage: "pencil") }
            })
        } else {
            content
        }
    }
}

struct MessageBranchControls: View {
    let currentIndex: Int
    let totalCount: Int
    let isEnabled: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onPrevious()
            } label: {
                Text("←")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled || !canGoPrevious)

            Text("\(currentIndex)/\(totalCount)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()

            Button {
                onNext()
            } label: {
                Text("→")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled || !canGoNext)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Version \(currentIndex) of \(totalCount)")
    }
}

struct ErrorBubbleView: View {
    let text: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text("An error occurred")
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .padding(.bottom, 2)

            Text(text.isEmpty ? "Unknown error" : text)
                .foregroundStyle(.white.opacity(0.95))
                .font(.subheadline)

            HStack {
                Spacer()
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.95), in: RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
        .shadow(color: ChatTheme.bubbleShadow, radius: 8, x: 0, y: 4)
    }
}

struct SystemTextBubble: View {
    @Bindable var message: ChatMessage
    @State private var showThink = false

    let thinkPreviewLines: Int
    let thinkFontSize: CGFloat
    let thinkFont: Font
    let showActionButtons: Bool
    let contentFingerprint: ContentFingerprint

    let onCopy: () -> Void
    let onRegenerate: () -> Void
    let onReadAloud: () -> Void
    private let renderCache = MessageRenderCache.shared

    var body: some View {
        let parts = renderCache.thinkParts(for: message.id, content: message.content, fingerprint: contentFingerprint)

        let thinkView = Group {
            if let think = parts.think {
                if parts.isClosed {
                    DisclosureGroup(isExpanded: $showThink) {
                        Text(think)
                            .font(thinkFont)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
                            .padding(.top, 4)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                            Text("Thinking Complete")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .contentShape(Rectangle())
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
                    .bubbleStyle(
                        isUser: false,
                        contentPadding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
                    )
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        DisclosureGroup(isExpanded: $showThink) {
                            Text(think)
                                .font(thinkFont)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
                                .padding(.top, 4)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "brain.head.profile")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                                Text("Thinking")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                        }

                        if !showThink {
                            TailLinesText(
                                text: think,
                                lines: thinkPreviewLines,
                                font: PlatformFontSpec(size: thinkFontSize, isMonospaced: true)
                            )
                            .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: contentMaxWidthForAssistant())
                    .bubbleStyle(
                        isUser: false,
                        contentPadding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
                    )
                }
            }
        }

        let bodyView = Group {
            if !parts.body.isEmpty {
                RichMarkdownView(markdown: parts.body)
                    .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }

        return VStack(alignment: .center, spacing: 8) {
            thinkView
            bodyView
            if parts.isClosed && !parts.body.isEmpty && showActionButtons {
                HStack(spacing: 6) {
                    Button { onCopy() } label: {
                        Image(systemName: "doc.on.doc")
                            #if os(macOS)
                            .font(.system(size: 12, weight: .semibold))
                            #else
                            .font(.system(size: 16, weight: .semibold))
                            #endif
                            .padding(2)
                            .accessibilityLabel("Copy")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button { onRegenerate() } label: {
                        Image(systemName: "arrow.clockwise")
                            #if os(macOS)
                            .font(.system(size: 12, weight: .semibold))
                            #else
                            .font(.system(size: 16, weight: .semibold))
                            #endif
                            .padding(2)
                            .accessibilityLabel("Regenerate")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button { onReadAloud() } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            #if os(macOS)
                            .font(.system(size: 12, weight: .semibold))
                            #else
                            .font(.system(size: 16, weight: .semibold))
                            #endif
                            .padding(2)
                            .accessibilityLabel("Read Aloud")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tint(ChatTheme.accent)
        .frame(maxWidth: .infinity, alignment: .center)
        .textSelection(.enabled)
    }
}

struct UserTextBubble: View {
    let text: String
    @State private var expanded = false
    private let maxCharacters = 1000

    var body: some View {
        let display = (expanded || text.count <= maxCharacters) ? text : (String(text.prefix(maxCharacters)) + "...")

        VStack(alignment: .trailing, spacing: 6) {
            Text(display)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .bubbleStyle(isUser: true)
                .frame(maxWidth: contentMaxWidthForUser(), alignment: .trailing)

            if text.count > maxCharacters {
                Button(expanded ? "Collapse" : "Show Full Message") {
                    withAnimation(.easeInOut) { expanded.toggle() }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
                .frame(maxWidth: contentMaxWidthForUser(), alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
