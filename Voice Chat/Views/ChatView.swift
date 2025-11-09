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
private struct EquatableRender<Value: Equatable, Content: View>: View, Equatable {
    static func == (lhs: EquatableRender<Value, Content>, rhs: EquatableRender<Value, Content>) -> Bool {
        lhs.value == rhs.value
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

struct ChatView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var speechInputManager: SpeechInputManager
    @ObservedObject var viewModel: ChatViewModel
    @State private var textFieldHeight: CGFloat = InputMetrics.defaultHeight
    @FocusState private var isInputFocused: Bool

    @State private var isShowingTextSelectionSheet = false
    @State private var textSelectionContent = ""

    @State private var inputOverflow: Bool = false
    @State private var showFullScreenComposer: Bool = false

    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

#if os(macOS)
    @State private var returnKeyMonitor: Any?
#endif

    // View model that coordinates the realtime voice overlay.
    @StateObject private var voiceOverlayVM = VoiceChatOverlayViewModel(
        speechInputManager: SpeechInputManager.shared,
        audioManager: GlobalAudioManager.shared
    )

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

    private var shouldAnchorBottom: Bool {
        let availableHeight = max(0, viewportHeight - messageListBottomInset)
        return contentHeight > (availableHeight + 1)
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
        floatingInputButtonHeight + 20
    }

    private var messageListBottomInset: CGFloat {
        floatingInputPanelHeight + 20
    }

    private var shouldDisplayAudioPlayer: Bool {
        audioManager.isShowingAudioPlayer && !audioManager.isRealtimeMode && !voiceOverlayVM.isPresented
    }

    private var trimmedUserMessage: String {
        viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack(alignment: .top) {
            PlatformColor.systemBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Divider().overlay(ChatTheme.separator).opacity(0)

                // Conversation content area
                Group {
                    if !voiceOverlayVM.isPresented {
                        GeometryReader { outerGeo in
                            ScrollView {
                                messageList(scrollTargetsEnabled: true)
                            }
                            .background(
                                Color.clear.preference(key: ViewportHeightKey.self, value: outerGeo.size.height)
                            )
                            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
                            .onPreferenceChange(ViewportHeightKey.self) { viewportHeight = $0 }
                            .defaultScrollAnchor(shouldAnchorBottom ? .bottom : .top)
                            .scrollDismissesKeyboard(.interactively)
                            .onTapGesture { isInputFocused = false }
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
            floatingInputPanel
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .onAppear {
            onMessagesCountChange(visibleMessages.count)
            viewModel.onUpdate = { [weak viewModel, weak chatSessionsViewModel] in
                guard let vm = viewModel, let store = chatSessionsViewModel else { return }
                if !store.chatSessions.contains(where: { $0.id == vm.chatSession.id }) {
                    store.addSession(vm.chatSession)
                } else {
                    store.persist(session: vm.chatSession, reason: .throttled)
                }
                onMessagesCountChange(vm.chatSession.messages.count)
            }
#if os(macOS)
            registerReturnKeyMonitor()
#endif
        }
        .onDisappear {
#if os(macOS)
            unregisterReturnKeyMonitor()
#endif
        }

        // Cross-platform presentation of the realtime voice overlay
#if os(iOS) || os(tvOS)
        .fullScreenCover(isPresented: $voiceOverlayVM.isPresented) {
            RealtimeVoiceOverlayView(
                viewModel: voiceOverlayVM,
                onClose: { }
            )
        }
#elseif os(macOS)
        // macOS renders the overlay as an always-on-top layer
        .overlay(
            Group {
                if voiceOverlayVM.isPresented {
                    RealtimeVoiceOverlayView(
                        viewModel: voiceOverlayVM,
                        onClose: { }
                    )
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
        )
#endif
#if os(iOS) || os(tvOS)
        .fullScreenCover(isPresented: $showFullScreenComposer) {
            FullScreenComposer(text: $viewModel.userMessage) {
                isInputFocused = true
            }
        }
#endif
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
        HStack(alignment: .center, spacing: 12) {
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
                .padding(.horizontal, InputMetrics.outerH)

                #if os(iOS) || os(tvOS)
                if inputOverflow {
                    Button {
                        showFullScreenComposer = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 8)
                    .accessibilityLabel("Open full screen editor")
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
                #endif
            }
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ChatTheme.subtleStroke.opacity(0.6), lineWidth: 0.75)
            )
            .background(Color.clear)
            .frame(minHeight: floatingInputButtonHeight)

            floatingTrailingButton
                .frame(minWidth: 44)
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(PlatformColor.systemBackground.opacity(0.75))
            }
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    private var floatingTrailingButton: some View {
        Group {
            if viewModel.isLoading {
                Button {
                    viewModel.cancelCurrentRequest()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                        .shadow(color: ChatTheme.bubbleShadow, radius: 4, x: 0, y: 2)
                        .accessibilityLabel("Stop Generation")
                }
                .buttonStyle(.plain)
            } else if trimmedUserMessage.isEmpty {
                Button {
                    openRealtimeVoiceOverlay()
                } label: {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ChatTheme.accent)
                        .shadow(color: ChatTheme.bubbleShadow, radius: 4, x: 0, y: 2)
                        .accessibilityLabel("Start Realtime Voice Conversation")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    sendIfPossible()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ChatTheme.accent)
                        .shadow(color: ChatTheme.bubbleShadow, radius: 4, x: 0, y: 2)
                        .accessibilityLabel("Send Message")
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: floatingInputButtonHeight)
    }

    @ViewBuilder
    private func messageList(scrollTargetsEnabled: Bool) -> some View {
        if scrollTargetsEnabled {
            messageListCore()
                .scrollTargetLayout()
                .padding(.horizontal, messageListHorizontalPadding)
                .padding(.vertical, 12)
                .padding(.bottom, messageListBottomInset)
                .frame(maxWidth: contentColumnMaxWidth())
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            messageListCore()
                .padding(.horizontal, messageListHorizontalPadding)
                .padding(.vertical, 12)
                .padding(.bottom, messageListBottomInset)
                .frame(maxWidth: contentColumnMaxWidth())
                .frame(maxWidth: .infinity, alignment: .center)
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
        }
        .background(
            GeometryReader { contentGeo in
                Color.clear.preference(key: ContentHeightKey.self, value: contentGeo.size.height)
            }
        )
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
        ChatView(viewModel: ChatViewModel(chatSession: session))
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .environmentObject(SpeechInputManager())
    }
}
