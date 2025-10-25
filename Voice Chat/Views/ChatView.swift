//
//  ChatView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import SwiftUI
import Foundation
import SwiftData

// MARK: - 等值渲染通用包装与快照键

/// 轻量等值包装：仅以 `value` 判断是否需要重绘，`content` 不参与比较。
private struct EquatableRender<Value: Equatable, Content: View>: View, Equatable {
    static func == (lhs: EquatableRender<Value, Content>, rhs: EquatableRender<Value, Content>) -> Bool {
        lhs.value == rhs.value
    }
    let value: Value
    let content: () -> Content
    var body: some View { content() }
}

/// 文本内容的轻量指纹，降低比较成本并避免引用型读取造成“旧视图读到新值”的误判。
private struct ContentFingerprint: Equatable {
    let utf16Count: Int
    let hash: Int
    static func make(_ s: String) -> ContentFingerprint {
        .init(utf16Count: s.utf16.count, hash: s.hashValue)
    }
}

/// VoiceMessage 的等值快照键：只包含会影响 UI 的纯值字段
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

    // ★ 实时语音 Overlay VM（MVVM）
    @StateObject private var voiceOverlayVM = VoiceChatOverlayViewModel()

    // 语音听写基准文本
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

                // ===================== 内容区 =====================
                Group {
                    if !voiceOverlayVM.isPresented {   // ★ 打开实时语音界面时：不渲染原聊天列表
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
                        // 占位：避免后台渲染
                        Color.clear.frame(height: 1)
                    }
                }

                // ===================== 编辑提示条 =====================
                if viewModel.isEditing, let _ = visibleMessages.last {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.orange)
                        Text("正在编辑")
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
                        .help("取消编辑并恢复显示")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PlatformColor.secondaryBackground.opacity(0.6))
                }

                // ===================== 输入区 =====================
                VStack(spacing: 10) {
                    HStack(alignment: .bottom, spacing: 10) {
                        // 自适应输入框
                        ZStack(alignment: .topLeading) {
                            if viewModel.userMessage.isEmpty {
                                Text("在这里输入消息…")
                                    .font(.system(size: 17))
                                    .foregroundColor(.secondary)
                                    .padding(.top, InputMetrics.outerV + InputMetrics.innerTop)
                                    .padding(.leading, InputMetrics.outerH + InputMetrics.innerLeading)
                                    .accessibilityHint("输入框占位提示")
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
                                .accessibilityLabel("全屏编辑")
                                .frame(maxWidth: .infinity, alignment: .topTrailing)
                            }
#endif
                        }
                        .background(ChatTheme.inputBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ChatTheme.subtleStroke, lineWidth: 1)
                        )

                        // ★ 语音听写（麦克风）按钮（保留）
                        Button {
                            toggleDictation()
                        } label: {
                            Image(systemName: speechInputManager.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(speechInputManager.isRecording ? .red : ChatTheme.accent)
                                .shadow(color: ChatTheme.bubbleShadow, radius: 4, x: 0, y: 2)
                                .accessibilityLabel(speechInputManager.isRecording ? "停止语音输入" : "语音输入")
                        }
                        .buttonStyle(.plain)
                        .help(speechInputManager.isRecording ? "停止语音输入" : "语音输入")

                        // ★ 右侧按钮
                        if viewModel.isLoading {
                            Button {
                                viewModel.cancelCurrentRequest()
                            } label: {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.red)
                                    .shadow(color: ChatTheme.bubbleShadow, radius: 4, x: 0, y: 2)
                                    .accessibilityLabel("停止")
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
                                        .accessibilityLabel("实时语音对话")
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
                                        .accessibilityLabel("发送")
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

        // ======== 平台化的“实时语音”面板呈现 ========
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
                    // iOS 下保持 Overlay 常驻，便于连续对话
                }
            )
            .environmentObject(speechInputManager)
            .environmentObject(audioManager)
            .onDisappear {
                if speechInputManager.isRecording { speechInputManager.stopRecording() }
            }
        }
        #elseif os(macOS)
        // ✅ macOS：用 overlay 全屏覆盖显示 RealtimeVoiceOverlayView
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
                // 仅最后一条在加载中时隐藏“复制/重试等”按钮
                let showButtons = !(viewModel.isLoading && (visibleMessages.last?.id == message.id))

                // 等值键：当消息正文或显隐状态未变化时跳过重绘
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

    // MARK: - 语音输入开关
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

    // MARK: - 打开实时语音覆盖层
    private func openRealtimeVoiceOverlay() {
        voiceOverlayVM.present()
    }
}

// MARK: - 预览

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
