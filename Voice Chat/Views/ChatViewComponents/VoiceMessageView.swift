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
    let onSelectText: (String) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onEditUserMessage: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void

    private let thinkPreviewLines: Int = 6
    private let thinkFontSize: CGFloat = 14
    private let thinkFont: Font = .system(size: 14, design: .monospaced)

    var body: some View {
        // Render error bubbles differently from regular messages.
        if message.content.hasPrefix("!error:") {
            return AnyView(
                HStack {
                    ErrorBubbleView(text: String(message.content.dropFirst("!error:".count)).trimmingCharacters(in: .whitespacesAndNewlines)) {
                        onRetry(message)
                    }
                    .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            )
        }

        let systemTextBubble = SystemTextBubble(
            message: message,
            thinkPreviewLines: thinkPreviewLines,
            thinkFontSize: thinkFontSize,
            thinkFont: thinkFont,
            showActionButtons: showActionButtons,
            onCopy: { copyToClipboard(message.content.extractThinkParts().body) },
            onRegenerate: { onRegenerate(message) },
            onReadAloud: { audioManager.startProcessing(text: message.content.extractThinkParts().body) }
        )

        return AnyView(
            HStack(alignment: .top) {
                if message.isUser { Spacer(minLength: 40) } else { Spacer(minLength: 0) }

                if message.isUser {
                    UserTextBubble(text: message.content)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    systemTextBubble
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
        )
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
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
                Button { copyToClipboard(bodyText) } label: { Label(L10n.Common.copy, systemImage: "doc.on.doc") }
                Button { onSelectText(bodyText) } label: { Label(L10n.Common.selectText, systemImage: "text.cursor") }
                Button { onEditUserMessage(message) } label: { Label(L10n.Common.edit, systemImage: "pencil") }
            })
        } else {
            content
        }
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
                Text(L10n.VoiceMessage.errorTitle)
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .padding(.bottom, 2)

            Group {
                if text.isEmpty {
                    Text(L10n.Common.unknownError)
                } else {
                    Text(text)
                }
            }
            .foregroundStyle(.white.opacity(0.95))
            .font(.subheadline)

            HStack {
                Spacer()
                Button {
                    onRetry()
                } label: {
                    Label(L10n.Common.retry, systemImage: "arrow.clockwise")
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

    let onCopy: () -> Void
    let onRegenerate: () -> Void
    let onReadAloud: () -> Void

    var body: some View {
        let parts = message.content.extractThinkParts()

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
                            Text(L10n.VoiceMessage.thinkingFinished)
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
                                Text(L10n.VoiceMessage.thinking)
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
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(L10n.Common.accessibilityCopy))

                    Button { onRegenerate() } label: {
                        Image(systemName: "arrow.clockwise")
                            #if os(macOS)
                            .font(.system(size: 12, weight: .semibold))
                            #else
                            .font(.system(size: 16, weight: .semibold))
                            #endif
                            .padding(2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(L10n.Common.accessibilityRegenerate))

                    Button { onReadAloud() } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            #if os(macOS)
                            .font(.system(size: 12, weight: .semibold))
                            #else
                            .font(.system(size: 16, weight: .semibold))
                            #endif
                            .padding(2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(L10n.Common.accessibilityReadAloud))
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
        let display = (expanded || text.count <= maxCharacters) ? text : (String(text.prefix(maxCharacters)) + "…")

        VStack(alignment: .trailing, spacing: 6) {
            Text(display)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .bubbleStyle(isUser: true)
                .frame(maxWidth: contentMaxWidthForUser(), alignment: .trailing)

            if text.count > maxCharacters {
                Button(expanded ? L10n.Common.showLess : L10n.Common.showMore) {
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
