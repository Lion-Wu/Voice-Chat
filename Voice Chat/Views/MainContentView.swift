//
//  MainContentView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/2/19.
//

#if os(iOS) || os(tvOS)

import Foundation
import SwiftUI

/// Primary container for iOS and iPadOS with top controls and the chat view.
struct MainContentView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    let onToggleSidebar: () -> Void

    /// Keeps track of the current session message count to control the compose button state.
    @State private var currentMessagesCount: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Toolbar
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

                // Chat content
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
