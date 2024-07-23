//
//  chatWithVoiceView.swift
//  Voice Chat
//
//  Created by 小吴苹果机器人 on 2024/1/8.
//

import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var isScrolling = false
    @State private var isNearBottom = true

    var body: some View {
        VStack {
            ScrollView {
                ScrollViewReader { scrollView in
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.messages) { message in
                            VoiceMessageView(message: message, viewModel: viewModel)
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
                    .onChange(of: viewModel.messages) { _ in
                        if isNearBottom && !isScrolling {
                            scrollToBottom(scrollView: scrollView, newMessages: viewModel.messages)
                        }
                    }
                }
            }

            if viewModel.isLoading {
                ProgressView()
                    .padding()
            }

            HStack {
                TextEditor(text: $viewModel.userMessage)
                    .frame(height: 40)
                    .padding(.horizontal, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                    .cornerRadius(8)
                    .onChange(of: viewModel.userMessage) { newValue in
                        if newValue.last == "\n" {
                            viewModel.userMessage.removeLast()
                            viewModel.sendMessage()
                        }
                    }

                Button(action: {
                    viewModel.sendMessage()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .imageScale(.large)
                }
            }
            .padding()
        }
        .navigationBarTitle("聊天界面", displayMode: .inline)
    }

    private func scrollToBottom(scrollView: ScrollViewProxy, newMessages: [ChatMessage]) {
        if !newMessages.isEmpty {
            isScrolling = true
            withAnimation(.easeIn(duration: 0.1)) {
                scrollView.scrollTo(newMessages.last!.id, anchor: .bottom)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isScrolling = false
            }
        }
    }
}

struct VoiceMessageView: View {
    let message: ChatMessage
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        HStack(alignment: .top) {
            if message.isUser {
                Spacer()
                TextBubble(text: message.content, isUser: true)
            } else {
                HStack(alignment: .top) {
                    Image(systemName: "person.circle.fill")
                        .imageScale(.large)
                        .foregroundColor(.blue)
                        .padding(.trailing, 5)
                        .alignmentGuide(.top) { d in d[.top] }
                    
                    TextBubble(text: message.content, isUser: false)
                        .alignmentGuide(.top) { d in d[.top] }
                    
                    Button(action: {
                        viewModel.getVoice(for: message.content)
                    }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .imageScale(.large)
                            .padding(.leading, 5)
                            .alignmentGuide(.top) { d in d[.top] }
                    }
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
                isUser ? Color.gray.opacity(0.2) : Color.clear
            )
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: isUser ? 25 : 0, style: .continuous))
            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isUser ? .trailing : .leading)
    }
}

#Preview {
    ChatView()
}
