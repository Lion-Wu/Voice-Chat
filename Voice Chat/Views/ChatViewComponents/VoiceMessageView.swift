//
//  VoiceMessageView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI
#if os(iOS) || os(macOS)
import QuickLook
import UniformTypeIdentifiers
#endif
import ImageIO
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct VoiceMessageView: View {
    let message: ChatMessage
    @EnvironmentObject var audioManager: GlobalAudioManager
    @State private var messagePreviewFileURL: URL?

    let showActionButtons: Bool
    let branchControlsEnabled: Bool
    let developerModeEnabled: Bool
    let maxBubbleWidth: CGFloat?
    let contentFingerprint: ContentFingerprint
    let onSelectText: (String) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onEditUserMessage: (ChatMessage) -> Void
    let onSwitchVersion: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void

    private let thinkPreviewLines: Int = 6
    private let thinkFontSize: CGFloat = 14

    init(
        message: ChatMessage,
        showActionButtons: Bool,
        branchControlsEnabled: Bool,
        developerModeEnabled: Bool,
        maxBubbleWidth: CGFloat? = nil,
        contentFingerprint: ContentFingerprint,
        onSelectText: @escaping (String) -> Void,
        onRegenerate: @escaping (ChatMessage) -> Void,
        onEditUserMessage: @escaping (ChatMessage) -> Void,
        onSwitchVersion: @escaping (ChatMessage) -> Void,
        onRetry: @escaping (ChatMessage) -> Void
    ) {
        self.message = message
        self.showActionButtons = showActionButtons
        self.branchControlsEnabled = branchControlsEnabled
        self.developerModeEnabled = developerModeEnabled
        self.maxBubbleWidth = maxBubbleWidth
        self.contentFingerprint = contentFingerprint
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
#if os(iOS) || os(macOS)
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

    #if os(iOS) || os(macOS)
    private func presentMessageAttachmentPreview(_ attachment: ChatImageAttachment) {
        let previous = messagePreviewFileURL
        messagePreviewFileURL = ChatImageQuickLookSupport.prepareTemporaryPreviewURL(for: attachment)
        if previous != messagePreviewFileURL {
            ChatImageQuickLookSupport.cleanupTemporaryPreviewURL(previous)
        }
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

#Preview {
    let message: ChatMessage = {
        let session = ChatSession(title: "Preview")
        let message = ChatMessage(
            content: "<think>\nReasoning preview...\n</think>\nHello from the assistant!",
            isUser: false,
            isActive: false,
            createdAt: Date(),
            deltaCount: 1,
            characterCount: 0,
            session: session
        )
        session.messages.append(message)
        return message
    }()
    let audio = GlobalAudioManager()

    VoiceMessageView(
        message: message,
        showActionButtons: true,
        branchControlsEnabled: true,
        developerModeEnabled: true,
        contentFingerprint: ContentFingerprint.make(message.content),
        onSelectText: { _ in },
        onRegenerate: { _ in },
        onEditUserMessage: { _ in },
        onSwitchVersion: { _ in },
        onRetry: { _ in }
    )
    .environmentObject(audio)
    .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
    .padding()
    .background(AppBackgroundView())
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

private struct ThinkingPreviewBubble: View {
    let think: String
    let isComplete: Bool
    let previewLines: Int
    let thinkFontSize: CGFloat

    @State private var isShowingFullText = false

    private var statusIconName: String {
        isComplete ? "checkmark.seal.fill" : "brain.head.profile"
    }

    private var statusColor: Color {
        isComplete ? .green : .orange
    }

    private var statusTextKey: LocalizedStringKey {
        isComplete ? "Thinking Complete" : "Thinking"
    }

    private var shouldShowPreview: Bool {
        !isComplete && !isShowingFullText
    }

    private var previewTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
        )
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingFullText = true
            }
        } label: {
            VStack(alignment: .leading, spacing: shouldShowPreview ? 8 : 0) {
                HStack(spacing: 6) {
                    Image(systemName: statusIconName)
                        .font(.subheadline)
                        .foregroundStyle(statusColor)

                    Text(statusTextKey)
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Spacer(minLength: 0)
                }

                if shouldShowPreview {
                    TailLinesText(
                        text: think,
                        lines: previewLines,
                        font: PlatformFontSpec(size: thinkFontSize, isMonospaced: true)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(previewTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusTextKey)
        .accessibilityHint("Open full reasoning")
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .bubbleStyle(
            isUser: false,
            contentPadding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        )
        .contentShape(Rectangle())
        .thinkDetailPresentation(
            isPresented: $isShowingFullText,
            think: think,
            title: statusTextKey,
            iconName: statusIconName,
            iconColor: statusColor
        )
        .animation(.easeInOut(duration: 0.2), value: shouldShowPreview)
    }
}

private struct ThinkingDetailView: View {
    let title: LocalizedStringKey
    let iconName: String
    let iconColor: Color
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.headline)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ScrollView {
                RichMarkdownView(markdown: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 680, maxWidth: 760, minHeight: 360, idealHeight: 620)
        #endif
    }
}

private struct ThinkDetailPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let think: String
    let title: LocalizedStringKey
    let iconName: String
    let iconColor: Color

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(isPresented: $isPresented, arrowEdge: .top) {
            ThinkingDetailView(
                title: title,
                iconName: iconName,
                iconColor: iconColor,
                text: think
            )
        }
        #else
        content.sheet(isPresented: $isPresented) {
            ThinkingDetailView(
                title: title,
                iconName: iconName,
                iconColor: iconColor,
                text: think
            )
            #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            #endif
        }
        #endif
    }
}

private extension View {
    func thinkDetailPresentation(
        isPresented: Binding<Bool>,
        think: String,
        title: LocalizedStringKey,
        iconName: String,
        iconColor: Color
    ) -> some View {
        modifier(
            ThinkDetailPresentationModifier(
                isPresented: isPresented,
                think: think,
                title: title,
                iconName: iconName,
                iconColor: iconColor
            )
        )
    }
}

struct SystemTextBubble: View {
    let message: ChatMessage
    @State private var isShowingMessageDetails = false
    @State private var isShowingCopyFeedback = false
    @State private var copyFeedbackToken = 0

    let thinkPreviewLines: Int
    let thinkFontSize: CGFloat
    let showActionButtons: Bool
    let developerModeEnabled: Bool
    let maxBubbleWidth: CGFloat?
    let contentFingerprint: ContentFingerprint

    let onCopy: () -> Void
    let onRegenerate: () -> Void
    let onReadAloud: () -> Void
    private let renderCache = MessageRenderCache.shared

    var body: some View {
        let parts = renderCache.thinkParts(for: message.id, content: message.content, fingerprint: contentFingerprint)

        let thinkView = Group {
            if let think = parts.think {
                ThinkingPreviewBubble(
                    think: think,
                    isComplete: parts.isClosed,
                    previewLines: thinkPreviewLines,
                    thinkFontSize: thinkFontSize
                )
                    .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
            }
        }

        let bodyView = Group {
            if !parts.body.isEmpty {
                RichMarkdownView(markdown: parts.body)
                    .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }

        return VStack(alignment: .center, spacing: 8) {
            thinkView
            bodyView
            if parts.isClosed && !parts.body.isEmpty && showActionButtons {
                HStack(spacing: 6) {
                    Button { handleCopy() } label: {
                        Image(systemName: isShowingCopyFeedback ? "checkmark" : "doc.on.doc")
                            #if os(macOS)
                            .font(.system(size: 12, weight: .semibold))
                            #else
                            .font(.system(size: 16, weight: .semibold))
                            #endif
                            .padding(2)
                            .frame(minWidth: 18, minHeight: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isShowingCopyFeedback ? Color.green : .secondary)
                    .accessibilityLabel(isShowingCopyFeedback ? Text("Copied") : Text("Copy"))

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

                    if developerModeEnabled {
                        Button { isShowingMessageDetails = true } label: {
                            Image(systemName: "info.circle")
                                #if os(macOS)
                                .font(.system(size: 12, weight: .semibold))
                                #else
                                .font(.system(size: 16, weight: .semibold))
                                #endif
                                .padding(2)
                                .accessibilityLabel("Details")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tint(ChatTheme.accent)
        .frame(maxWidth: .infinity, alignment: .center)
        .textSelection(.enabled)
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
            MessageDetailsView(message: message)
        }
    }

    private func handleCopy() {
        onCopy()
        withAnimation(.easeInOut(duration: 0.18)) {
            isShowingCopyFeedback = true
        }
        copyFeedbackToken += 1
    }
}

struct UserTextBubble: View {
    let text: String
    let attachments: [ChatImageAttachment]
    let maxBubbleWidth: CGFloat?
    let onPreviewImage: (ChatImageAttachment) -> Void
    @State private var expanded = false
    private let maxCharacters = 1000

    var body: some View {
        let display = (expanded || text.count <= maxCharacters) ? text : (String(text.prefix(maxCharacters)) + "...")

        VStack(alignment: .trailing, spacing: 6) {
            if !attachments.isEmpty {
                ChatImageAttachmentStrip(
                    attachments: attachments,
                    removable: false,
                    maxItemSize: 160,
                    onPreview: onPreviewImage,
                    onRemove: nil,
                    horizontalAlignment: .trailing
                )
                .frame(maxWidth: contentMaxWidthForUser(availableWidth: maxBubbleWidth), alignment: .trailing)
            }

            if !display.isEmpty {
                Text(display)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .bubbleStyle(isUser: true)
                    .frame(maxWidth: contentMaxWidthForUser(availableWidth: maxBubbleWidth), alignment: .trailing)
            }

            if text.count > maxCharacters {
                Button(expanded ? "Collapse" : "Show Full Message") {
                    withAnimation(.easeInOut) { expanded.toggle() }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
                .frame(maxWidth: contentMaxWidthForUser(availableWidth: maxBubbleWidth), alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct ChatImageAttachmentStrip: View {
    let attachments: [ChatImageAttachment]
    let removable: Bool
    let maxItemSize: CGFloat
    let onPreview: (ChatImageAttachment) -> Void
    let onRemove: ((ChatImageAttachment) -> Void)?
    let horizontalAlignment: HorizontalAlignment

    init(
        attachments: [ChatImageAttachment],
        removable: Bool,
        maxItemSize: CGFloat,
        onPreview: @escaping (ChatImageAttachment) -> Void,
        onRemove: ((ChatImageAttachment) -> Void)?,
        horizontalAlignment: HorizontalAlignment = .leading
    ) {
        self.attachments = attachments
        self.removable = removable
        self.maxItemSize = maxItemSize
        self.onPreview = onPreview
        self.onRemove = onRemove
        self.horizontalAlignment = horizontalAlignment
    }

    private var stripAlignment: Alignment {
        horizontalAlignment == .trailing ? .trailing : .leading
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        ChatImageAttachmentItem(
                            attachment: attachment,
                            removable: removable,
                            maxItemSize: maxItemSize,
                            onPreview: onPreview,
                            onRemove: onRemove
                        )
                    }
                }
                .frame(minWidth: proxy.size.width, alignment: stripAlignment)
                .padding(.vertical, 2)
            }
        }
        .frame(height: maxItemSize + 4)
    }
}

private struct ChatImageAttachmentItem: View {
    let attachment: ChatImageAttachment
    let removable: Bool
    let maxItemSize: CGFloat
    let onPreview: (ChatImageAttachment) -> Void
    let onRemove: ((ChatImageAttachment) -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onPreview(attachment)
            } label: {
                Group {
                    if let image = chatSwiftUIImage(for: attachment, maxItemSize: maxItemSize) {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .frame(width: maxItemSize, height: maxItemSize)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            if removable, let onRemove {
                Button {
                    onRemove(attachment)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove image"))
            }
        }
    }
}

#if os(iOS) || os(macOS)
@MainActor
enum ChatImageQuickLookSupport {
    private static let directoryName = "VoiceChatQuickLook"

    static func prepareTemporaryPreviewURL(for attachment: ChatImageAttachment) -> URL? {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let fileExtension = preferredFileExtension(for: attachment.mimeType)
        let filename = "attachment-\(attachment.id.uuidString)-\(UUID().uuidString).\(fileExtension)"
        let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)

        do {
            try attachment.data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    static func cleanupTemporaryPreviewURL(_ fileURL: URL?) {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func preferredFileExtension(for mimeType: String) -> String {
        let normalized = mimeType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if let type = UTType(mimeType: normalized),
           let fileExtension = type.preferredFilenameExtension,
           !fileExtension.isEmpty {
            return fileExtension
        }

        switch normalized {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/heic", "image/heif":
            return "heic"
        case "image/tiff":
            return "tiff"
        case "image/bmp":
            return "bmp"
        default:
            return "jpg"
        }
    }
}
#endif

private final class ChatImageThumbnailCache: @unchecked Sendable {
    static let shared = ChatImageThumbnailCache()

    #if os(iOS) || os(tvOS) || os(watchOS)
    private let cache = NSCache<NSString, UIImage>()
    #elseif os(macOS)
    private let cache = NSCache<NSString, NSImage>()
    #endif

    private init() {
        cache.countLimit = 256
    }

    #if os(iOS) || os(tvOS) || os(watchOS)
    func image(for attachment: ChatImageAttachment, maxPixelSize: Int) -> UIImage? {
        let key = cacheKey(for: attachment, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let decoded = decodeThumbnail(from: attachment.data, maxPixelSize: maxPixelSize) else {
            return nil
        }
        cache.setObject(decoded, forKey: key)
        return decoded
    }
    #elseif os(macOS)
    func image(for attachment: ChatImageAttachment, maxPixelSize: Int) -> NSImage? {
        let key = cacheKey(for: attachment, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let decoded = decodeThumbnail(from: attachment.data, maxPixelSize: maxPixelSize) else {
            return nil
        }
        cache.setObject(decoded, forKey: key)
        return decoded
    }
    #endif

    private func cacheKey(for attachment: ChatImageAttachment, maxPixelSize: Int) -> NSString {
        "\(attachment.id.uuidString)-\(max(1, maxPixelSize))" as NSString
    }
}

@MainActor
private func chatSwiftUIImage(for attachment: ChatImageAttachment, maxItemSize: CGFloat) -> Image? {
    let maxPixelSize = max(1, Int((maxItemSize * chatThumbnailDisplayScale()).rounded(.up)))
#if os(iOS) || os(tvOS) || os(watchOS)
    guard let image = ChatImageThumbnailCache.shared.image(for: attachment, maxPixelSize: maxPixelSize) else { return nil }
    return Image(uiImage: image)
#elseif os(macOS)
    guard let image = ChatImageThumbnailCache.shared.image(for: attachment, maxPixelSize: maxPixelSize) else { return nil }
    return Image(nsImage: image)
#else
    return nil
#endif
}

@MainActor
private func chatThumbnailDisplayScale() -> CGFloat {
#if os(iOS) || os(tvOS) || os(watchOS)
    return UIScreen.main.scale
#elseif os(macOS)
    return NSScreen.main?.backingScaleFactor ?? 2
#else
    return 1
#endif
}

#if os(iOS) || os(tvOS) || os(watchOS)
private func decodeThumbnail(from data: Data, maxPixelSize: Int) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return UIImage(data: data)
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false,
        kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return UIImage(data: data)
    }
    return UIImage(cgImage: cgImage)
}
#elseif os(macOS)
private func decodeThumbnail(from data: Data, maxPixelSize: Int) -> NSImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return NSImage(data: data)
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false,
        kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return NSImage(data: data)
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}
#endif
