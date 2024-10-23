//
//  chatWithVoiceView.swift
//  Voice Chat
//
//  Created by 小吴苹果机器人 on 2024/1/8.
//

import SwiftUI

struct ScrollOffsetPreferenceKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

struct DetectableScrollView<Content: View>: View {
    let axes: Axis.Set
    let showsIndicators: Bool
    let content: Content
    let onScroll: () -> Void
    
    // State variable to track user scrolling
    @State private var isUserScrolling: Bool = false

    init(axes: Axis.Set = .vertical,
         showsIndicators: Bool = true,
         onScroll: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
        self.onScroll = onScroll
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .global).minY)
            }
            .frame(height: 0)
            content
        }
        // Use simultaneousGesture to allow both ScrollView and DragGesture to recognize gestures
        .simultaneousGesture(
            DragGesture()
                .onChanged { _ in
                    // User started scrolling
                    if !isUserScrolling {
                        isUserScrolling = true
                        onScroll()
                    }
                }
                .onEnded { _ in
                    // User ended scrolling after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isUserScrolling = false
                    }
                }
        )
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { _ in
            // No longer need to check isUserScrolling here
            // The onScroll is now called directly from the DragGesture
        }
    }
}

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var audioManager: GlobalAudioManager
    @State private var isScrolling = false
    @State private var isNearBottom = true

    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                DetectableScrollView(onScroll: {
                    isInputFocused = false
                }) {
                    ScrollViewReader { scrollView in
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
                            if isNearBottom && !isScrolling {
                                scrollToBottom(scrollView: scrollView, newMessages: newValue)
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
                        .focused($isInputFocused)
                        .frame(height: 40)
                        .padding(.horizontal, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray, lineWidth: 1)
                        )
                        .cornerRadius(8)

                    Button(action: {
                        viewModel.sendMessage()
                        // Removed: isInputFocused = false to keep the keyboard visible
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .imageScale(.large)
                    }
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
    @EnvironmentObject var audioManager: GlobalAudioManager

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
                        audioManager.startProcessing(text: message.content)
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
                isUser ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2)
            )
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isUser ? .trailing : .leading)
    }
}

#Preview {
    ChatView()
        .environmentObject(GlobalAudioManager.shared)
}
