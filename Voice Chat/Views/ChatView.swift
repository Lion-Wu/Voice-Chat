//
//  ChatView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import SwiftUI

struct ChatView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var audioManager: GlobalAudioManager
    @StateObject private var viewModel: ChatViewModel
    @State private var textFieldHeight: CGFloat = 40
    @FocusState private var isInputFocused: Bool

    // 用于“选择文本”功能时的弹窗
    @State private var isShowingTextSelectionSheet: Bool = false
    @State private var textSelectionContent: String = ""

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
                            if viewModel.isLoading {
                                LoadingBubble()
                            }
                        }
                        .padding() // 整体内边距
                        .onChange(of: viewModel.chatSession.messages.count) { _, _ in
                            if let lastMessage = viewModel.chatSession.messages.last, lastMessage.isUser {
                                scrollToBottom(scrollView: scrollView)
                            }
                        }
                    }
                    // 在 UIKit 平台上支持滚动时自动收起键盘（iOS、tvOS、watchOS）
                    #if os(iOS) || os(tvOS) || os(watchOS)
                    .scrollDismissesKeyboard(.interactively)
                    #endif
                    .onTapGesture {
                        isInputFocused = false
                    }
                }

                // 输入区域
                HStack(spacing: 8) {
                    AutoSizingTextEditor(text: $viewModel.userMessage, height: $textFieldHeight)
                        .focused($isInputFocused)
                        .frame(height: textFieldHeight)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)

                    Button(action: {
                        viewModel.sendMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 8)
                    .disabled(viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .background(RoundedRectangle(cornerRadius: 15).fill(Color.gray.opacity(0.1)))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
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
                    guard let viewModel = viewModel, let chatSessionsViewModel = chatSessionsViewModel else { return }
                    if !chatSessionsViewModel.chatSessions.contains(viewModel.chatSession) {
                        chatSessionsViewModel.addSession(viewModel.chatSession)
                    } else {
                        chatSessionsViewModel.saveChatSessions()
                    }
                }
            }
        }
        // “选择文本”功能所用的弹出窗口
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
                    ToolbarItem(placement: .automatic) { // macOS 兼容
                        Button("完成") {
                            isShowingTextSelectionSheet = false
                        }
                    }
                    #else
                    ToolbarItem(placement: .navigationBarTrailing) { // iOS / iPadOS
                        Button("完成") {
                            isShowingTextSelectionSheet = false
                        }
                    }
                    #endif
                }
            }
            // iPad 下默认是 sheet，这里无需特别处理 macOS 的弹窗
        }
    }

    private func scrollToBottom(scrollView: ScrollViewProxy) {
        if let lastMessage = viewModel.chatSession.messages.last {
            withAnimation(.easeIn(duration: 0.1)) {
                scrollView.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    private func showSelectTextSheet(with text: String) {
        textSelectionContent = text
        isShowingTextSelectionSheet = true
    }
}

// MARK: - 气泡中的长按菜单及其逻辑

struct VoiceMessageView: View {
    @ObservedObject var message: ChatMessage
    @EnvironmentObject var audioManager: GlobalAudioManager

    /// 选择文本回调
    let onSelectText: (String) -> Void

    /// 重新生成回调（仅系统消息有）
    let onRegenerate: (ChatMessage) -> Void

    /// 编辑用户消息回调（仅用户消息有）
    let onEditUserMessage: (ChatMessage) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isUser {
                Spacer()
                TextBubble(text: message.content, isUser: true)
            } else {
                // 系统消息不显示左侧头像，也不再显示额外的朗读按钮
                TextBubble(text: message.content, isUser: false)
            }
        }
        .padding(.vertical, 5)
        // 长按或右键菜单
        .contextMenu {
            Button {
                copyToClipboard(message.content)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            
            Button {
                onSelectText(message.content)
            } label: {
                Label("选择文本", systemImage: "text.cursor")
            }
            
            if message.isUser {
                // 用户消息：复制、选择文本、编辑
                Button {
                    onEditUserMessage(message)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            } else {
                // 系统消息：复制、选择文本、重新生成、朗读
                Button {
                    onRegenerate(message)
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
                Button {
                    audioManager.startProcessing(text: message.content)
                } label: {
                    Label("朗读", systemImage: "speaker.wave.2.fill")
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS) || os(tvOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
        #endif
    }
}

// MARK: - 输入框自适应高度

struct AutoSizingTextEditor: View {
    @Binding var text: String
    @Binding var height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("在这里输入消息...")
                    .foregroundColor(.gray)
                    .padding(EdgeInsets(top: 12, leading: 8, bottom: 8, trailing: 8))
                    .font(.system(size: 17))
            }

            Text(text)
                .font(.system(size: 17))
                .foregroundColor(.clear)
                .padding(8)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onChange(of: text) { _, _ in
                                DispatchQueue.main.async {
                                    height = geometry.size.height
                                }
                            }
                    }
                )

            TextEditor(text: $text)
                .font(.system(size: 17))
                .padding(4)
                .background(Color.clear)
        }
        .frame(height: max(height, 40))
    }
}

// MARK: - 文字气泡

struct TextBubble: View {
    let text: String
    let isUser: Bool
    @State private var isExpanded = false
    private let maxCharacters = 1000
    /// 固定左右空白（系统消息右侧、用户消息左侧）
    private let horizontalMargin: CGFloat = 40

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading) {
            // 仅用户消息需要折叠逻辑，系统消息全部显示
            Text(isUser
                 ? (isExpanded ? text : String(text.prefix(maxCharacters)) + (text.count > maxCharacters ? "..." : ""))
                 : text)
                .padding(12)
                .background(isUser ? Color.gray.opacity(0.2) : Color.clear)
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                // 限制气泡宽度，让两侧各留固定空白
                .frame(maxWidth: maxWidth - horizontalMargin, alignment: isUser ? .trailing : .leading)

            if isUser && text.count > maxCharacters {
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? "收起" : "显示完整信息")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var maxWidth: CGFloat {
        #if os(iOS) || os(tvOS)
        return UIScreen.main.bounds.width
        #elseif os(macOS)
        return NSScreen.main?.frame.width ?? 800
        #else
        return 600
        #endif
    }
}

struct LoadingIndicatorView: View {
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        Circle()
            .frame(width: 20, height: 20)
            .foregroundColor(.gray)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    scale = 1.2
                }
            }
    }
}

struct LoadingBubble: View {
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
        let chatSession = ChatSession()
        ChatView(chatSession: chatSession)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(ChatSessionsViewModel())
    }
}
