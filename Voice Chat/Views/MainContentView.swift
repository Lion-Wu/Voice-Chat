//
//  MainContentView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/2/19.
//

#if os(iOS) || os(tvOS)

import Foundation
import SwiftUI

/// iOS/iPadOS 主视图：顶部左/右按钮，下面是 ChatView。
struct MainContentView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    let onToggleSidebar: () -> Void

    /// 由子视图 ChatView 回传的当前会话消息数，用于决定右上角加号可用性。
    @State private var currentMessagesCount: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // 顶部条
                HStack {
                    Button(action: { onToggleSidebar() }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                    }

                    Spacer()

                    Button(action: { chatSessionsViewModel.startNewSession() }) {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                    .disabled(currentMessagesCount == 0)
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                Divider()

                // 聊天区域
                if let selectedSession = chatSessionsViewModel.selectedSession {
                    ChatView(
                        chatSession: selectedSession,
                        onMessagesCountChange: { newCount in
                            if currentMessagesCount != newCount {
                                currentMessagesCount = newCount
                            }
                        }
                    )
                    .id(selectedSession.id)
                } else {
                    Text("No chat. Creating one...")
                        .onAppear {
                            chatSessionsViewModel.startNewSession()
                        }
                }
            }
        }
        .onAppear {
            if chatSessionsViewModel.chatSessions.isEmpty {
                chatSessionsViewModel.startNewSession()
            }
            currentMessagesCount = chatSessionsViewModel.selectedSession?.messages.count ?? 0
        }
    }
}

#endif
