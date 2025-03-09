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
                    .disabled(currentChatIsEmpty)
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                Divider()

                // 聊天区域
                if let selectedSession = chatSessionsViewModel.selectedSession {
                    ChatView(chatSession: selectedSession)
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
        }
    }

    private var currentChatIsEmpty: Bool {
        guard let session = chatSessionsViewModel.selectedSession else {
            return true
        }
        return session.messages.isEmpty
    }
}

#endif
