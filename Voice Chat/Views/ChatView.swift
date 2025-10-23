//
//  ChatView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import SwiftUI
import Foundation
import SwiftData

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

    // Dedicated view model for the real-time voice overlay.
    @StateObject private var voiceOverlayVM = VoiceChatOverlayViewModel()

    // Base text used to merge dictated input with typed content.
    @State private var dictationBaseText: String = ""

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

                // MARK: - Conversation Content
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
                        // Render a placeholder when the overlay is visible to avoid off-screen work.
                        Color.clear.frame(height: 1)
                    }
                }

                // MARK: - Editing Banner
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
                        .help("Cancel editing and restore the message list")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PlatformColor.secondaryBackground.opacity(0.6))
                }

                // MARK: - Composer
                VStack(spacing: 10) {
                    HStack(alignment: .bottom, spacing: 10) {
                        // Adaptive input field
                        ZStack(alignment: .topLeading) {
                            if viewModel.userMessage.isEmpty {
                                Text("Type your message here...")
                                    .font(.system(size: 17))
                                    .foregroundColor(.secondary)
                                    .padding(.top, InputMetrics.outerV + InputMetrics.innerTop)
                                    .padding(.leading, InputMetrics.outerH + InputMetrics.innerLeading)
                                    .accessibilityHint("Message composer placeholder")
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
                                    self.inputOverflow = overflow && isPhone()
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
                                .accessibilityLabel("Enter full screen composer")
                                .frame(maxWidth: .infinity, alignment: .topTrailing)
                            }
#endif
                        }
                        .background(ChatTheme.inputBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ChatTheme.subtleStroke, lineWidth: 1)
                        )

                        // Voice dictation control
                        Button {
                            toggleDictation()
                        } label: {
                            Image(systemName: speechInputManager.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(speechInputManager.isRecording ? .red : ChatTheme.accent)
                                .shadow(color: ChatTheme.bubbleShadow, radius: 4, x: 0, y: 2)
                                .accessibilityLabel(speechInputManager.isRecording ? "Stop voice input" : "Start voice input")
                        }
                        .buttonStyle(.plain)
                        .help(speechInputManager.isRecording ? "Stop voice input" : "Start voice input")

                        // Contextual action: stop when loading, send when text exists, otherwise open voice overlay.
                        if viewModel.isLoading {
                            Button {
                                viewModel.cancelCurrentRequest()
                            } label: {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.red)
                                    .shadow(color: ChatTheme.bubbleShadow, radius: 4, x: 0, y: 2)
                                    .accessibilityLabel("Stop")
                            }
                            .buttonStyle(.plain)
                        } else {
                            if viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                // No text: show waveform icon to open the real-time voice overlay.
                                Button {
                                    openRealtimeVoiceOverlay()
                                } label: {
                                    Image(systemName: "waveform.circle.fill")
                                        .font(.system(size: 32, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(ChatTheme.accent)
                                        .shadow(color: ChatTheme.bubbleShadow, radius: 4, x: 0, y: 2)
                                        .accessibilityLabel("Start real-time voice conversation")
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
                                        .accessibilityLabel("Send")
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

        // MARK: - Real-time Voice Overlay Presentation
        #if os(iOS) || os(tvOS)
        .fullScreenCover(isPresented: $voiceOverlayVM.isPresented) {
            RealtimeVoiceOverlayView(
                onClose: {
                    voiceOverlayVM.isPresented = false
                    if speechInputManager.isRecording { speechInputManager.stopRecording() }
                },
                onTextFinal: { text in
                    viewModel.prepareRealtimeTTSForNextAssistant()
                    viewModel.userMessage = text
                    viewModel.sendMessage()
                    // Keep the overlay available for consecutive turns on iOS.
                }
            )
            .environmentObject(speechInputManager)
            .environmentObject(audioManager)
            .onDisappear {
                if speechInputManager.isRecording { speechInputManager.stopRecording() }
            }
        }
        #elseif os(macOS)
        // Display the overlay as a full-screen layer on macOS as well.
        .overlay(
            Group {
                if voiceOverlayVM.isPresented {
                    RealtimeVoiceOverlayView(
                        onClose: {
                            voiceOverlayVM.isPresented = false
                            if speechInputManager.isRecording { speechInputManager.stopRecording() }
                        },
                        onTextFinal: { text in
                            viewModel.prepareRealtimeTTSForNextAssistant()
                            viewModel.userMessage = text
                            viewModel.sendMessage()
                            // Keep the overlay available for consecutive turns on macOS.
                        }
                    )
                    .environmentObject(speechInputManager)
                    .environmentObject(audioManager)
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
                VoiceMessageView(
                    message: message,
                    showActionButtons: !(viewModel.isLoading && (visibleMessages.last?.id == message.id)),
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

    // MARK: - Dictation Toggle
    private func toggleDictation() {
        if speechInputManager.isRecording {
            speechInputManager.stopRecording()
            return
        }
        dictationBaseText = viewModel.userMessage
        let needsSpace: Bool = {
            guard let last = dictationBaseText.last else { return false }
            return !last.isWhitespace && !dictationBaseText.isEmpty
        }()

        Task { @MainActor in
            await speechInputManager.startRecording(
                onPartial: { partial in
                    let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.userMessage = dictationBaseText + (p.isEmpty ? "" : (needsSpace ? " " : "") + p)
                },
                onFinal: { finalText in
                    let f = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.userMessage = dictationBaseText + (f.isEmpty ? "" : (needsSpace ? " " : "") + f)
                }
            )
        }
    }

    // MARK: - Present Voice Overlay
    private func openRealtimeVoiceOverlay() {
        voiceOverlayVM.present()
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
