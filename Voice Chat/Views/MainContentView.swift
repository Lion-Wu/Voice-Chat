//
//  MainContentView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/2/19.
//

#if os(iOS) || os(tvOS)

import Foundation
import SwiftUI

/// Primary view for iOS and iPadOS that shows a top bar and the chat content.
struct MainContentView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var voiceOverlayViewModel: VoiceChatOverlayViewModel

    let onToggleSidebar: () -> Void

    private var selectedSessionTitle: String {
        chatSessionsViewModel.selectedSession?.title ?? "Voice Chat"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                Group {
                    if let selectedSession = chatSessionsViewModel.selectedSession {
                        ChatView(
                            viewModel: chatSessionsViewModel.viewModel(for: selectedSession)
                        )
                        .id(selectedSession.id)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No Chat Selected")
                                .font(.title3.weight(.semibold))
                            Text("Start a new conversation to begin talking.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task {
                            chatSessionsViewModel.startNewSession()
                        }
                    }
                }
            }
            .navigationTitle(selectedSessionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !voiceOverlayViewModel.isPresented {
                        Button(action: { onToggleSidebar() }) {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel(Text("Toggle chat list"))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { chatSessionsViewModel.startNewSession() }) {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                    }
                    .accessibilityLabel("New Chat")
                    .disabled(!chatSessionsViewModel.canStartNewSession)
                }
            }
        }
        .onAppear {
            if chatSessionsViewModel.chatSessions.isEmpty {
                chatSessionsViewModel.startNewSession()
            }
        }
    }
}

#endif
