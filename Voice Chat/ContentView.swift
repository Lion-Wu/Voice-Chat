//
//  ContentView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                onConversationTap: { conversation in
                    selectConversation(conversation)
                },
                onOpenSettings: { showingSettings = true }
            )
        } detail: {
            ChatViewContainer()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .toolbar {
            // On macOS, you automatically get a sidebar toggle, but on iOS/iPadOS, we can add a button manually.
            // The reference code uses a similar approach, providing a button to show/hide sidebar.
            #if os(iOS)
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button(action: toggleSidebar) {
                    Image(systemName: columnVisibility == .all ? "sidebar.left" : "sidebar.right")
                }
                .help("Toggle Sidebar")
            }
            #endif

            ToolbarItemGroup(placement: .automatic) {
                Button(action: {
                    startNewConversation()
                }) {
                    Image(systemName: "plus")
                }
                .help("New Chat")
                .disabled(!chatSessionsViewModel.canStartNewSession)
            }
        }
        .onAppear {
            // Ensure there's always at least one chat session
            if chatSessionsViewModel.chatSessions.isEmpty {
                chatSessionsViewModel.startNewSession()
            }
        }
    }

    @ViewBuilder
    private func ChatViewContainer() -> some View {
        if let selectedSession = chatSessionsViewModel.selectedSession {
            ChatView(chatSession: selectedSession)
                .id(selectedSession.id)
        } else {
            Text("No chat selected")
                .font(.largeTitle)
                .foregroundColor(.gray)
        }
    }

    private func selectConversation(_ session: ChatSession) {
        chatSessionsViewModel.selectedSession = session
    }

    private func startNewConversation() {
        chatSessionsViewModel.startNewSession()
    }

    private func toggleSidebar() {
        withAnimation {
            if columnVisibility == .all {
                columnVisibility = .detailOnly
            } else {
                columnVisibility = .all
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(SettingsManager.shared)
            .environmentObject(ChatSessionsViewModel())
    }
}
