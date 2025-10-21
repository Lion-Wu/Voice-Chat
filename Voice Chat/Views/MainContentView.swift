//
//  MainContentView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/2/19.
//

#if os(iOS) || os(tvOS)

import Foundation
import SwiftUI

/// Primary content view for iOS and iPadOS with a top bar and the chat surface.
struct MainContentView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    let onToggleSidebar: () -> Void

    /// Tracks the number of messages to decide whether the add button should be enabled.
    @State private var currentMessagesCount: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Top toolbar
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
                    .accessibilityLabel(Text(L10n.Sidebar.newChat))
                    .disabled(currentMessagesCount == 0)
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                Divider()

                // Chat area
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
                    Text(L10n.Chat.creatingNewChat)
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
