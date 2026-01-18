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
        (chatSessionsViewModel.selectedSession ?? chatSessionsViewModel.draftSession).title
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                let activeSession = chatSessionsViewModel.selectedSession ?? chatSessionsViewModel.draftSession
                ChatView(viewModel: chatSessionsViewModel.viewModel(for: activeSession))
                    .id(activeSession.id)
            }
            .navigationTitle(selectedSessionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { onToggleSidebar() }) {
                        Image(systemName: "sidebar.left")
                    }
                    .accessibilityLabel(Text("Toggle chat list"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { chatSessionsViewModel.startNewSession() }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Chat")
                    .disabled(!chatSessionsViewModel.canStartNewSession)
                }
            }
        }
    }
}

#endif
