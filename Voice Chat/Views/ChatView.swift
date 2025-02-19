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
                                VoiceMessageView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                        .onChange(of: viewModel.chatSession.messages.count) { _, _ in
                            scrollToBottom(scrollView: scrollView)
                        }
                    }
                    .onTapGesture {
                        isInputFocused = false
                    }
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                }

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
        .navigationTitle(viewModel.chatSession.title)
        .onAppear {
            // Wrap state changes in DispatchQueue.main.async to avoid publishing changes during view updates
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
    }

    private func scrollToBottom(scrollView: ScrollViewProxy) {
        if let lastMessage = viewModel.chatSession.messages.last {
            withAnimation(.easeIn(duration: 0.1)) {
                scrollView.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

struct AutoSizingTextEditor: View {
    @Binding var text: String
    @Binding var height: CGFloat
    @State private var showPlaceholder = true

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
                .background(GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            height = geometry.size.height
                        }
                        .onChange(of: text) { _, _ in
                            DispatchQueue.main.async {
                                height = geometry.size.height
                            }
                        }
                })

            TextEditor(text: $text)
                .font(.system(size: 17))
                .padding(4)
                .background(Color.clear)
                .onAppear {
                    showPlaceholder = text.isEmpty
                }
                .onChange(of: text) { _, _ in
                    showPlaceholder = text.isEmpty
                }
        }
        .frame(height: max(height, 40))
    }
}

struct VoiceMessageView: View {
    @ObservedObject var message: ChatMessage
    @EnvironmentObject var audioManager: GlobalAudioManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isUser {
                Spacer()
                TextBubble(text: message.content, isUser: true)
            } else {
                Image(systemName: "person.circle.fill")
                    .imageScale(.large)
                    .foregroundColor(.blue)
                    .padding(.top, 5)

                TextBubble(text: message.content, isUser: false)

                Button(action: {
                    audioManager.startProcessing(text: message.content)
                }) {
                    Image(systemName: "speaker.wave.2.fill")
                        .imageScale(.large)
                        .padding(.top, 5)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct TextBubble: View {
    let text: String
    let isUser: Bool
    @State private var isExpanded = false
    private let maxCharacters = 1000

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading) {
            Text(isExpanded ? text : String(text.prefix(maxCharacters)) + (text.count > maxCharacters ? "..." : ""))
                .padding(12)
                .background(isUser ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .frame(maxWidth: maxWidth * 0.7, alignment: isUser ? .trailing : .leading)

            if text.count > maxCharacters {
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

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let chatSession = ChatSession()
        ChatView(chatSession: chatSession)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(ChatSessionsViewModel())
    }
}
