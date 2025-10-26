//
//  ChatView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import SwiftUI
import Foundation
import SwiftData

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
    @StateObject private var viewModel: ChatViewModel
    @State private var textFieldHeight: CGFloat = 0
    @FocusState private var isInputFocused: Bool

    @State private var isShowingTextSelectionSheet = false
    @State private var textSelectionContent = ""

    @State private var inputOverflow: Bool = false
    @State private var showFullScreenComposer: Bool = false

    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    // View model that coordinates the realtime voice overlay.
    @StateObject private var voiceOverlayVM = VoiceChatOverlayViewModel(
        speechInputManager: SpeechInputManager.shared,
        audioManager: GlobalAudioManager.shared
    )

    var onMessagesCountChange: (Int) -> Void = { _ in }

    init(chatSession: ChatSession, onMessagesCountChange: @escaping (Int) -> Void = { _ in }) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatSession: chatSession))
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
        contentHeight > (viewportHeight + 1)
    }

    private var messageListHorizontalPadding: CGFloat {
        #if os(macOS)
        return 16
        #else
        return 8
        #endif
    }

    var body: some View {
        ZStack(alignment: .top) {
            PlatformColor.systemBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Divider().overlay(ChatTheme.separator).opacity(0)

                // Conversation content area
                Group {
                    if !voiceOverlayVM.isPresented {
                        if #available(iOS 17.0, tvOS 17.0, macOS 14.0, watchOS 10.0, *) {
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
                            ScrollView {
                                messageList(scrollTargetsEnabled: false)
                            }
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

                // Input area
                VStack(spacing: 10) {
                    HStack(alignment: .bottom, spacing: 10) {
                        // Auto-sizing input field
                        ZStack(alignment: .topLeading) {
                            if viewModel.userMessage.isEmpty {
                                Text("Type your message...")
                                    .font(.system(size: 17))
                                    .foregroundColor(.secondary)
                                    .padding(.top, InputMetrics.outerV + InputMetrics.innerTop)
                                    .padding(.leading, InputMetrics.outerH + InputMetrics.innerLeading)
                                    .accessibilityHint("Message field placeholder")
                            }

#if os(macOS)
                            AutoSizingTextEditor(
                                text: $viewModel.userMessage,
                                height: $textFieldHeight,
                                maxLines: platformMaxLines(),
                                onOverflowChange: { _ in },
                                onCommit: {
                                    let trimmed = viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !viewModel.isLoading, !trimmed.isEmpty else { return }
                                    viewModel.sendMessage()
                                }
                            )
                            .focused($isInputFocused)
                            .frame(height: textFieldHeight)
                            .padding(.vertical, InputMetrics.outerV)
                            .padding(.horizontal, InputMetrics.outerH)
#else
                            AutoSizingTextEditor(
                                text: $viewModel.userMessage,
                                height: $textFieldHeight,
                                maxLines: platformMaxLines(),
                                onOverflowChange: { overflow in
                                    let newValue = overflow && isPhone()
                                    if newValue != inputOverflow {
                                        DispatchQueue.main.async {
                                            inputOverflow = newValue
                                        }
                                    }
                                }
                            )
                            .focused($isInputFocused)
                            .frame(height: textFieldHeight)
                            .padding(.vertical, InputMetrics.outerV)
                            .padding(.horizontal, InputMetrics.outerH)
#endif

#if os(iOS) || os(tvOS)
                            if inputOverflow && isPhone() {
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
                        .background(ChatTheme.inputBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ChatTheme.subtleStroke, lineWidth: 1)
                        )

                        // Trailing controls
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
                        } else {
                            if viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                                    viewModel.sendMessage()
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
                    }
                    .padding(.horizontal, 12)

                    Rectangle()
                        .fill(LinearGradient(colors: [ChatTheme.separator, .clear], startPoint: .top, endPoint: .bottom))
                        .frame(height: 1)
                        .opacity(0.6)
                        .padding(.horizontal, 12)
                }
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(
                    VStack(spacing: 0) {
                        Divider().overlay(ChatTheme.separator)
                        Spacer(minLength: 0)
                    }
                )
            }

            if audioManager.isShowingAudioPlayer {
                VStack {
                    AudioPlayerView()
                        .environmentObject(audioManager)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: audioManager.isShowingAudioPlayer)
            }
        }
        #if os(macOS)
        .navigationTitle(viewModel.chatSession.title)
        #endif
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
    }

    @ViewBuilder
    private func messageList(scrollTargetsEnabled: Bool) -> some View {
        if scrollTargetsEnabled {
            messageListCore()
                .scrollTargetLayout()
                .padding(.horizontal, messageListHorizontalPadding)
                .padding(.vertical, 12)
                .frame(maxWidth: contentColumnMaxWidth())
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            messageListCore()
                .padding(.horizontal, messageListHorizontalPadding)
                .padding(.vertical, 12)
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
        ChatView(chatSession: session)
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .environmentObject(SpeechInputManager())
    }
}
