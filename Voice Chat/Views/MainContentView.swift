//
//  MainContentView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/2/19.
//

#if os(iOS) || os(tvOS)

import Foundation
import SwiftUI

/// iOS/iPadOS 主视图：顶部左/右按钮，下面是 ChatView
struct MainContentView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    let onToggleSidebar: () -> Void

    // 由子视图 ChatView 回传的当前会话消息数，用于实时决定右上角加号可用性
    @State private var currentMessagesCount: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // 自定义顶部条
                HStack {
                    // 左上角按钮：打开或关闭侧边栏
                    Button(action: {
                        onToggleSidebar()
                    }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                    }

                    Spacer()

                    // 右上角按钮：新建聊天
                    Button(action: {
                        chatSessionsViewModel.startNewSession()
                    }) {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                    .disabled(currentMessagesCount == 0) // 当当前会话没有消息时置灰；一旦有消息由子视图立即回传启用
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                Divider()

                // 聊天区域
                if let selectedSession = chatSessionsViewModel.selectedSession {
                    ChatView(
                        chatSession: selectedSession,
                        onMessagesCountChange: { newCount in
                            // 子视图主动上报消息数，驱动右上角加号按钮的可用状态
                            if currentMessagesCount != newCount {
                                currentMessagesCount = newCount
                            }
                        }
                    )
                    .id(selectedSession.id)
                } else {
                    // 若无选中会话，自动新建一个
                    Text("No chat. Creating one...")
                        .onAppear {
                            chatSessionsViewModel.startNewSession()
                        }
                }
            }
        }
        .onAppear {
            // 如果启动时没有会话，自动新建
            if chatSessionsViewModel.chatSessions.isEmpty {
                chatSessionsViewModel.startNewSession()
            }
            // 同步一次初始可用状态
            currentMessagesCount = chatSessionsViewModel.selectedSession?.messages.count ?? 0
        }
    }
}

#endif
