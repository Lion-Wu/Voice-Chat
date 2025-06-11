//
//  ChatView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import SwiftUI

// MARK: - ─────────── 帮助扩展 ────────────

private struct ThinkParts {
    let think: String?      // 思考链内容
    let isClosed: Bool      // 是否已出现 </think>
    let body: String        // 正文
}

private extension String {
    /// 把字符串按 <think>…</think> 拆成三段
    func extractThinkParts() -> ThinkParts {
        guard let start = range(of: "<think>") else {
            return ThinkParts(think: nil, isClosed: true, body: self)
        }
        let afterStart = self[start.upperBound...]
        if let end = afterStart.range(of: "</think>") {
            let thinkContent = String(afterStart[..<end.lowerBound])
            let bodyContent  = String(afterStart[end.upperBound...])
            return ThinkParts(think: thinkContent, isClosed: true, body: bodyContent)
        } else {
            // 尚未闭合
            let thinkContent = String(afterStart)
            return ThinkParts(think: thinkContent, isClosed: false, body: "")
        }
    }
}

// MARK: - ─────────── 视图模型 & 主要视图 ────────────

struct ChatView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var audioManager: GlobalAudioManager
    @StateObject private var viewModel: ChatViewModel
    @State private var textFieldHeight: CGFloat = 40
    @FocusState private var isInputFocused: Bool

    // 选择文本弹窗
    @State private var isShowingTextSelectionSheet = false
    @State private var textSelectionContent = ""

    init(chatSession: ChatSession) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatSession: chatSession))
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                ScrollViewReader { scrollView in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.chatSession.messages) { message in
                                VoiceMessageView(
                                    message: message,
                                    onSelectText: { showSelectTextSheet(with: $0) },
                                    onRegenerate: { viewModel.regenerateSystemMessage($0) },
                                    onEditUserMessage: { viewModel.editUserMessage($0) }
                                )
                                .id(message.id)
                            }
                            if viewModel.isLoading { LoadingBubble() }
                        }
                        .padding()
                        .onChange(of: viewModel.chatSession.messages.count) { _, _ in
                            if let last = viewModel.chatSession.messages.last, last.isUser {
                                scrollToBottom(scrollView: scrollView)
                            }
                        }
                    }
                    #if os(iOS) || os(tvOS) || os(watchOS)
                    .scrollDismissesKeyboard(.interactively)
                    #endif
                    .onTapGesture { isInputFocused = false }
                }

                // 输入区域
                HStack(spacing: 8) {
                    AutoSizingTextEditor(
                        text: $viewModel.userMessage,
                        height: $textFieldHeight,
                        onCommit: {
                            #if os(macOS)
                            viewModel.sendMessage()
                            #endif
                        }
                    )
                    .focused($isInputFocused)
                    .frame(height: textFieldHeight)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)

                    Button {
                        viewModel.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 8)
                    .disabled(viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .background(RoundedRectangle(cornerRadius: 15).fill(Color.gray.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                .padding()
            }

            // 语音播放视图
            if audioManager.isShowingAudioPlayer {
                VStack {
                    AudioPlayerView()
                        .environmentObject(audioManager)
                    Spacer()
                }
                .transition(.move(edge: .top))
                .animation(.easeInOut, value: audioManager.isShowingAudioPlayer)
            }
        }
        #if os(macOS)
        .navigationTitle(viewModel.chatSession.title)
        #endif
        .onAppear {
            viewModel.onUpdate = { [weak viewModel, weak chatSessionsViewModel] in
                DispatchQueue.main.async {
                    guard let vm = viewModel, let store = chatSessionsViewModel else { return }
                    if !store.chatSessions.contains(vm.chatSession) {
                        store.addSession(vm.chatSession)
                    } else {
                        store.saveChatSessions()
                    }
                }
            }
        }
        // 选择文本弹窗
        .sheet(isPresented: $isShowingTextSelectionSheet) {
            NavigationView {
                ScrollView {
                    Text(textSelectionContent)
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle("选择文本")
                .toolbar {
                    #if os(macOS)
                    ToolbarItem { Button("完成") { isShowingTextSelectionSheet = false } }
                    #else
                    ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { isShowingTextSelectionSheet = false } }
                    #endif
                }
            }
        }
    }

    private func scrollToBottom(scrollView: ScrollViewProxy) {
        if let last = viewModel.chatSession.messages.last {
            withAnimation(.easeIn(duration: 0.1)) {
                scrollView.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func showSelectTextSheet(with text: String) {
        textSelectionContent = text
        isShowingTextSelectionSheet = true
    }
}

// MARK: - ─────────── 气泡视图 ────────────

struct VoiceMessageView: View {
    @ObservedObject var message: ChatMessage
    @EnvironmentObject var audioManager: GlobalAudioManager

    let onSelectText: (String) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onEditUserMessage: (ChatMessage) -> Void

    var body: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 0)
            if message.isUser {
                UserTextBubble(text: message.content)
            } else {
                SystemTextBubble(message: message)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contextMenu {
            let parts = message.content.extractThinkParts()
            let bodyText = parts.body
            Button { copyToClipboard(bodyText) } label: { Label("复制", systemImage: "doc.on.doc") }
            Button { onSelectText(bodyText) } label: { Label("选择文本", systemImage: "text.cursor") }

            if message.isUser {
                Button { onEditUserMessage(message) } label: { Label("编辑", systemImage: "pencil") }
            } else {
                Button { onRegenerate(message) } label: { Label("重新生成", systemImage: "arrow.clockwise") }
                Button { audioManager.startProcessing(text: bodyText) } label: { Label("朗读", systemImage: "speaker.wave.2.fill") }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS) || os(tvOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - ─────────── 用户/系统气泡实现 ────────────

/// 用户消息气泡（含折叠长文）
private struct UserTextBubble: View {
    let text: String
    @State private var expanded = false
    private let maxCharacters = 1000
    private let horizontalMargin: CGFloat = 40
    private let preferredMaxWidth: CGFloat = 525   // 缩紧至原来的75%

    var body: some View {
        let display = expanded || text.count <= maxCharacters
            ? text
            : String(text.prefix(maxCharacters)) + "…"

        VStack(alignment: .center, spacing: 4) {
            Text(display)
                .padding(12)
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .frame(maxWidth: bubbleWidth, alignment: .trailing)

            if text.count > maxCharacters {
                Button(expanded ? "收起" : "显示完整信息") {
                    withAnimation { expanded.toggle() }
                }
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.top, 2)
            }
        }
    }

    private var bubbleWidth: CGFloat {
        #if os(iOS) || os(tvOS)
        min(UIScreen.main.bounds.width - horizontalMargin, preferredMaxWidth)
        #elseif os(macOS)
        min((NSScreen.main?.frame.width ?? 800) - horizontalMargin, preferredMaxWidth)
        #else
        preferredMaxWidth
        #endif
    }
}

/// 系统消息气泡（自动处理 <think> … </think>）
private struct SystemTextBubble: View {
    @ObservedObject var message: ChatMessage
    @State private var showThink = false
    private let horizontalMargin: CGFloat = 40
    private let preferredMaxWidth: CGFloat = 525

    var body: some View {
        let parts = message.content.extractThinkParts()

        VStack(alignment: .leading, spacing: 2) {
            if let think = parts.think {
                DisclosureGroup(isExpanded: $showThink) {
                    Text(think)
                        .frame(maxWidth: bubbleWidth, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Text(parts.isClosed ? "思考完毕" : "思考中")
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.gray.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .frame(maxWidth: bubbleWidth)
            }

            if !parts.body.isEmpty {
                Text(parts.body)
                    .padding(12)
                    .frame(maxWidth: bubbleWidth, alignment: .leading)
            }
        }
    }

    private var bubbleWidth: CGFloat {
        #if os(iOS) || os(tvOS)
        min(UIScreen.main.bounds.width - horizontalMargin, preferredMaxWidth)
        #elseif os(macOS)
        min((NSScreen.main?.frame.width ?? 800) - horizontalMargin, preferredMaxWidth)
        #else
        preferredMaxWidth
        #endif
    }
}

// MARK: - ─────────── 输入框自适应 ────────────

#if os(macOS)
private struct AutoSizingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = CommitTextView()
        textView.isEditable = true
        textView.font = .systemFont(ofSize: 17)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        if nsView.string != text { nsView.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoSizingTextEditor
        init(parent: AutoSizingTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            let used = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero
            parent.height = max(40, used.height + 16)
        }
    }

    final class CommitTextView: NSTextView {
        var onCommit: () -> Void = {}
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 {
                if event.modifierFlags.contains(.shift) {
                    super.keyDown(with: event)
                } else {
                    self.window?.makeFirstResponder(nil)
                    onCommit()
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
#else
private struct AutoSizingTextEditor: View {
    @Binding var text: String
    @Binding var height: CGFloat
    var onCommit: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("在这里输入消息…")
                    .foregroundColor(.gray)
                    .padding(.top, 12)
                    .padding(.leading, 8)
                    .font(.system(size: 17))
            }

            Text(text)
                .font(.system(size: 17))
                .foregroundColor(.clear)
                .padding(8)
                .background(GeometryReader { geo in
                    Color.clear.onChange(of: text) { _, _ in
                        DispatchQueue.main.async { height = geo.size.height }
                    }
                })

            TextEditor(text: $text)
                .font(.system(size: 17))
                .padding(4)
                .background(Color.clear)
        }
        .frame(height: max(height, 40))
    }
}
#endif

// MARK: - ─────────── Loading 指示 ────────────

private struct LoadingIndicatorView: View {
    @State private var scale: CGFloat = 0.8
    var body: some View {
        Circle()
            .frame(width: 20, height: 20)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    scale = 1.2
                }
            }
    }
}

private struct LoadingBubble: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LoadingIndicatorView()
                .padding(12)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            Spacer()
        }
        .padding(.vertical, 5)
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let session = ChatSession()
        ChatView(chatSession: session)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(ChatSessionsViewModel())
    }
}
