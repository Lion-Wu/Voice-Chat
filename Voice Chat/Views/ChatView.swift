//
//  ChatView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var audioManager: GlobalAudioManager
    @State private var isNearBottom = true

    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                ScrollViewReader { scrollView in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.messages) { message in
                                VoiceMessageView(message: message)
                                    .onAppear {
                                        if message.id == viewModel.messages.last?.id {
                                            isNearBottom = true
                                        }
                                    }
                                    .onDisappear {
                                        if message.id == viewModel.messages.last?.id {
                                            isNearBottom = false
                                        }
                                    }
                            }
                        }
                        .padding()
                        .onChange(of: viewModel.messages) { newValue, _ in
                            if isNearBottom {
                                scrollToBottom(scrollView: scrollView, newMessages: newValue)
                            }
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

                HStack {
                    TextEditor(text: $viewModel.userMessage)
                        .focused($isInputFocused)
                        .frame(minHeight: 40, maxHeight: 100)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
                        .cornerRadius(8)

                    Button(action: {
                        viewModel.sendMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                    .padding(.leading, 5)
                }
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
        .navigationTitle("Chat Interface")
    }

    private func scrollToBottom(scrollView: ScrollViewProxy, newMessages: [ChatMessage]) {
        if let lastMessage = newMessages.last {
            withAnimation(.easeIn(duration: 0.1)) {
                scrollView.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

struct VoiceMessageView: View {
    let message: ChatMessage
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

    var body: some View {
        Text(text)
            .padding(12)
            .background(
                isUser ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2)
            )
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .frame(maxWidth: maxWidth * 0.7, alignment: isUser ? .trailing : .leading)
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
        ChatView()
            .environmentObject(GlobalAudioManager.shared)
    }
}
