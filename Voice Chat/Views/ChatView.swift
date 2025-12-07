//
//  ChatView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import SwiftUI
import Foundation
import SwiftData

#if os(macOS)
import AppKit
#endif

// MARK: - Equatable Rendering Helpers

/// Wrapper that invalidates the view only when the equatable value changes.
@MainActor
private struct EquatableRender<Value: Equatable, Content: View>: View, Equatable {
    nonisolated static func == (lhs: EquatableRender<Value, Content>, rhs: EquatableRender<Value, Content>) -> Bool {
        // Access the main-actor-isolated value under explicit isolation; safe because value is immutable.
        MainActor.assumeIsolated {
            lhs.value == rhs.value
        }
    }
    let value: Value
    let content: () -> Content
    var body: some View { content() }
}

/// Lightweight fingerprint used to compare message content without scanning the entire string.
private struct ContentFingerprint: Equatable {
    let utf16Count: Int
    let hash: Int
    static func make(_ s: String) -> ContentFingerprint {
        .init(utf16Count: s.utf16.count, hash: s.hashValue)
    }
}

/// Equatable key for message rendering that keeps only UI-relevant fields.
private struct VoiceMessageEqKey: Equatable {
    let id: UUID
    let isUser: Bool
    let isActive: Bool
    let showActionButtons: Bool
    let contentFP: ContentFingerprint
}

private enum ScrollTarget: Hashable {
    case bottom
}

struct ChatView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var speechInputManager: SpeechInputManager
    @EnvironmentObject var errorCenter: AppErrorCenter
    @ObservedObject var viewModel: ChatViewModel
    @State private var textFieldHeight: CGFloat = InputMetrics.defaultHeight
    @FocusState private var isInputFocused: Bool

    @State private var isShowingTextSelectionSheet = false
    @State private var textSelectionContent = ""

    @State private var inputOverflow: Bool = false
    @State private var showFullScreenComposer: Bool = false

    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var bottomAnchorMaxY: CGFloat = 0
    @State private var showScrollToBottomButton: Bool = false
    @State private var scrollProxy: ScrollViewProxy?

#if os(macOS)
    @State private var returnKeyMonitor: Any?
#endif

    // View model that coordinates the realtime voice overlay.
    @EnvironmentObject private var voiceOverlayVM: VoiceChatOverlayViewModel

    var onMessagesCountChange: (Int) -> Void = { _ in }

    init(viewModel: ChatViewModel, onMessagesCountChange: @escaping (Int) -> Void = { _ in }) {
        self.viewModel = viewModel
        self.onMessagesCountChange = onMessagesCountChange
    }

    private var orderedMessages: [ChatMessage] {
        viewModel.chatSession.messages.sorted { $0.createdAt < $1.createdAt }
    }

    private var visibleMessages: [ChatMessage] {
        guard let baseID = viewModel.editingBaseMessageID,
              let idx = orderedMessages.firstIndex(where: { $0.id == baseID }) else {
            return orderedMessages
        }
        return Array(orderedMessages.prefix(idx + 1))
    }

    /// Height of the scrollable content excluding the spacer that keeps it clear of the floating input.
    private var effectiveContentHeight: CGFloat {
        max(0, contentHeight - messageListBottomInset)
    }

    private var shouldAnchorBottom: Bool {
        guard viewportHeight > 0 else { return false }
        return effectiveContentHeight > (viewportHeight + 1)
    }

    private var messageListHorizontalPadding: CGFloat {
        #if os(macOS)
        return 16
        #else
        return 8
        #endif
    }

    private var floatingInputButtonHeight: CGFloat {
        textFieldHeight + InputMetrics.outerV * 2
    }

    private var floatingInputPanelHeight: CGFloat {
        floatingInputButtonHeight + 16
    }

    private var messageListBottomInset: CGFloat {
        floatingInputPanelHeight + 20
    }

    private var noticeBottomPadding: CGFloat {
        // Keep the banner close to the composer while leaving a narrow gap.
        max(8, messageListBottomInset - 22)
    }

    // Negative offset so the banner begins under the composer and reveals upward.
    private var noticeHiddenOffset: CGFloat {
        -(floatingInputPanelHeight / 1.8)
    }

    private var shouldDisplayAudioPlayer: Bool {
        audioManager.isShowingAudioPlayer && !audioManager.isRealtimeMode && !voiceOverlayVM.isPresented
    }

    private var trimmedUserMessage: String {
        viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack(alignment: .top) {

            VStack(spacing: 0) {
                Divider().overlay(ChatTheme.separator).opacity(0)

                // Conversation content area
                Group {
                    if !voiceOverlayVM.isPresented {
                        GeometryReader { outerGeo in
                            ScrollViewReader { proxy in
                                ScrollView {
                                    messageList(scrollTargetsEnabled: true)
                                }
                                .coordinateSpace(name: "ChatScroll")
                                .background(
                                    Color.clear.preference(key: ViewportHeightKey.self, value: outerGeo.size.height)
                                )
                                .onPreferenceChange(ContentHeightKey.self) {
                                    contentHeight = $0
                                    updateScrollToBottomVisibility()
                                }
                                .onPreferenceChange(ViewportHeightKey.self) {
                                    viewportHeight = $0
                                    updateScrollToBottomVisibility()
                                }
                                .onPreferenceChange(BottomAnchorKey.self) { value in
                                    bottomAnchorMaxY = value
                                    updateScrollToBottomVisibility()
                                }
                                .defaultScrollAnchor(shouldAnchorBottom ? .bottom : .top)
                                .scrollDismissesKeyboard(.interactively)
                                .onTapGesture { isInputFocused = false }
                                .onAppear {
                                    scrollProxy = proxy
                                    DispatchQueue.main.async {
                                        scrollToBottom(animated: false)
                                    }
                                }
                            }
                        }
                    } else {
                        // Placeholder to avoid rendering work while the overlay is visible.
                        Color.clear.frame(height: 1)
                    }
                }

                // Editing banner
                if viewModel.isEditing, let _ = visibleMessages.last {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.orange)
                        Text("Editing")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            viewModel.cancelEditing()
                            isInputFocused = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel editing and restore the conversation")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PlatformColor.secondaryBackground.opacity(0.6))
                }

            }

            if shouldDisplayAudioPlayer {
                VStack {
                    AudioPlayerView()
                        .environmentObject(audioManager)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: shouldDisplayAudioPlayer)
            }
        }
        #if os(macOS)
        .navigationTitle(viewModel.chatSession.title)
        #endif
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if showScrollToBottomButton {
                    scrollToBottomButton
                        .transition(
                            .move(edge: .bottom)
                                .combined(with: .opacity)
                        )
                }

                floatingInputPanel
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .overlay(alignment: .bottom) {
            if !errorCenter.notices.isEmpty {
                ErrorNoticeStack(
                    notices: errorCenter.notices,
                    onDismiss: { notice in
                        errorCenter.dismiss(notice)
                    }
                )
                // Start hidden behind the composer: offset up by composer height so it slides from under it.
                .padding(.bottom, noticeBottomPadding)
                .offset(y: noticeHiddenOffset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(0)
            }
        }
        .onAppear {
            onMessagesCountChange(visibleMessages.count)
#if os(macOS)
            registerReturnKeyMonitor()
#endif
        }
        .onDisappear {
#if os(macOS)
            unregisterReturnKeyMonitor()
#endif
        }

#if os(iOS) || os(tvOS)
        .fullScreenCover(isPresented: $showFullScreenComposer) {
            FullScreenComposer(text: $viewModel.userMessage) {
                isInputFocused = true
            }
        }
#endif
        .onChange(of: visibleMessages.count) { _, _ in
            if !showScrollToBottomButton {
                scrollToBottom()
            }
        }
        .onChange(of: viewModel.chatSession.messages.count) { _, newValue in
            onMessagesCountChange(newValue)
        }
    }

    private func sendIfPossible() {
        let trimmed = trimmedUserMessage
        guard !trimmed.isEmpty, !viewModel.isLoading else { return }
        viewModel.sendMessage()
    }

    private func handleOverflowChange(_ overflow: Bool) {
        let shouldShowEditorExpander = overflow
        if shouldShowEditorExpander != inputOverflow {
            DispatchQueue.main.async {
                inputOverflow = shouldShowEditorExpander
            }
        }
    }

#if os(macOS)
    private func registerReturnKeyMonitor() {
        guard returnKeyMonitor == nil else { return }
        returnKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleMacReturnKey(event)
        }
    }

    private func unregisterReturnKeyMonitor() {
        if let monitor = returnKeyMonitor {
            NSEvent.removeMonitor(monitor)
            returnKeyMonitor = nil
        }
    }

    private func handleMacReturnKey(_ event: NSEvent) -> NSEvent? {
        let returnKeyCodes: Set<UInt16> = [36, 76]
        guard returnKeyCodes.contains(event.keyCode) else { return event }
        guard isInputFocused else { return event }

        let modifierMask = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let blockingMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        if modifierMask.intersection(blockingMask).isEmpty {
            sendIfPossible()
            return nil
        }

        return event
    }
#endif

    private var floatingInputPanel: some View {
        HStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if viewModel.userMessage.isEmpty {
                        Text("Type your message...")
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                            .padding(.top, InputMetrics.outerV + InputMetrics.innerTop)
                            .padding(.leading, InputMetrics.outerH + InputMetrics.innerLeading)
                            .accessibilityHint("Message field placeholder")
                    }

                    AutoSizingTextEditor(
                        text: $viewModel.userMessage,
                        height: $textFieldHeight,
                        maxLines: platformMaxLines(),
                        onOverflowChange: handleOverflowChange
                    )
                    .focused($isInputFocused)
                    .frame(height: textFieldHeight)
                    .padding(.vertical, InputMetrics.outerV)
                    .padding(.leading, InputMetrics.outerH)
                    .padding(.trailing, 6)

                    #if os(iOS) || os(tvOS)
                    if inputOverflow {
                        Button {
                            showFullScreenComposer = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                        .padding(.trailing, 8)
                        .accessibilityLabel("Open full screen editor")
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                    }
                    #endif
                }
                .frame(maxWidth: .infinity)

                floatingTrailingButton
            }
            .padding(.vertical, 8)
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(PlatformColor.systemBackground.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(ChatTheme.subtleStroke.opacity(0.35), lineWidth: 0.75)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                    .blur(radius: 26)
                    .opacity(0.82)
                    .padding(.horizontal, -18)
                    .frame(height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                            .blur(radius: 10)
                            .blendMode(.plusLighter)
                    )
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.16)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .blur(radius: 14)
                    )
                    .offset(y: 16)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.1), radius: 14, x: 10, y: 12)
            .shadow(color: Color.black.opacity(0.1), radius: 14, x: -10, y: 12)
            .shadow(color: Color.black.opacity(0.14), radius: 26, x: 0, y: 28)
        }
    }

    private var floatingTrailingButton: some View {
        Group {
            if viewModel.isLoading {
                Button {
                    viewModel.cancelCurrentRequest()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Stop Generation")
                }
                .buttonStyle(.plain)
            } else if trimmedUserMessage.isEmpty {
                Button {
                    openRealtimeVoiceOverlay()
                } label: {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ChatTheme.accent)
                        .accessibilityLabel("Start Realtime Voice Conversation")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    sendIfPossible()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ChatTheme.accent)
                        .accessibilityLabel("Send Message")
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 38, height: 38)
    }

    private var scrollToBottomButton: some View {
        Button {
            scrollToBottom()
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: scrollButtonSize, height: scrollButtonSize)
                .contentShape(Circle())
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .stroke(ChatTheme.subtleStroke.opacity(0.5), lineWidth: 0.6)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("Scroll to bottom")
    }

    private var scrollButtonSize: CGFloat {
        #if os(iOS) || os(tvOS)
        return 40
        #else
        return 34
        #endif
    }

    @ViewBuilder
    private func messageList(scrollTargetsEnabled: Bool) -> some View {
        let content = messageListCore()
            .padding(.horizontal, messageListHorizontalPadding)
            .padding(.top, 12)
            .frame(maxWidth: contentColumnMaxWidth())
            .frame(maxWidth: .infinity, alignment: .center)

        if scrollTargetsEnabled {
            content.scrollTargetLayout()
        } else {
            content
        }
    }

    @ViewBuilder
    private func messageListCore() -> some View {
        VStack(spacing: 12) {
            ForEach(visibleMessages) { message in
                // Hide action buttons while the newest message is still streaming.
                let showButtons = !(viewModel.isLoading && (visibleMessages.last?.id == message.id))

                // Skip re-rendering when the message content and state have not changed.
                let key = VoiceMessageEqKey(
                    id: message.id,
                    isUser: message.isUser,
                    isActive: message.isActive,
                    showActionButtons: showButtons,
                    contentFP: .make(message.content)
                )

                EquatableRender(value: key) {
                    VoiceMessageView(
                        message: message,
                        showActionButtons: showButtons,
                        onSelectText: { showSelectTextSheet(with: $0) },
                        onRegenerate: { viewModel.regenerateSystemMessage($0) },
                        onEditUserMessage: { msg in
                            viewModel.beginEditUserMessage(msg)
                            isInputFocused = true
                        },
                        onRetry: { errMsg in
                            viewModel.retry(afterErrorMessage: errMsg)
                        }
                    )
                }
                .id(message.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: visibleMessages.map(\.id))
            }

            if viewModel.isPriming {
                AssistantAlignedLoadingBubble()
            }

            Color.clear
                .frame(height: messageListBottomInset)
                .id(ScrollTarget.bottom)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BottomAnchorKey.self, value: proxy.frame(in: .named("ChatScroll")).maxY)
                    }
                )
        }
        .background(
            GeometryReader { contentGeo in
                Color.clear.preference(key: ContentHeightKey.self, value: contentGeo.size.height)
            }
        )
    }

    private func scrollToBottom(animated: Bool = true) {
        guard let proxy = scrollProxy else { return }
        let action = {
            proxy.scrollTo(ScrollTarget.bottom, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
        }
    }

    private func updateScrollToBottomVisibility() {
        guard viewportHeight > 0 else {
            if showScrollToBottomButton {
                showScrollToBottomButton = false
            }
            return
        }

        let bottomDistance = max(0, bottomAnchorMaxY - viewportHeight)
        let shouldShow = bottomDistance > 24
        if shouldShow != showScrollToBottomButton {
            withAnimation(.easeInOut(duration: 0.2)) {
                showScrollToBottomButton = shouldShow
            }
        }
    }

    private func showSelectTextSheet(with text: String) {
        textSelectionContent = text
        isShowingTextSelectionSheet = true
    }

    private func openRealtimeVoiceOverlay() {
        guard !voiceOverlayVM.isPresented else { return }
        voiceOverlayVM.presentSession { text in
            viewModel.prepareRealtimeTTSForNextAssistant()
            viewModel.userMessage = text
            viewModel.sendMessage()
        }
    }
}

// MARK: - Preview

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let session = ChatSession()
        let speechManager = SpeechInputManager()
        let overlayVM = VoiceChatOverlayViewModel(
            speechInputManager: speechManager,
            audioManager: GlobalAudioManager.shared,
            errorCenter: AppErrorCenter.shared
        )
        return ChatView(viewModel: ChatViewModel(chatSession: session))
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .environmentObject(speechManager)
            .environmentObject(overlayVM)
            .environmentObject(AppErrorCenter.shared)
    }
}
