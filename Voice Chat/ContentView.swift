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
        #if os(macOS)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                onConversationTap: { conversation in
                    selectConversation(conversation)
                },
                onOpenSettings: { showingSettings = true }
            )
        } detail: {
            if let selectedSession = chatSessionsViewModel.selectedSession {
                ChatView(chatSession: selectedSession)
                    .id(selectedSession.id)
            } else {
                Text("No chat selected")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                    .onAppear {
                        ensureAtLeastOneSession()
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(settingsManager)
        }
        .toolbar {
            ToolbarItem {
                Button(action: startNewConversation) {
                    Image(systemName: "plus")
                }
                .help("New Chat")
                .disabled(!chatSessionsViewModel.canStartNewSession)
            }
        }
        .onAppear { ensureAtLeastOneSession() }
        #else
        SideMenuContainerRepresentable()
            .environmentObject(chatSessionsViewModel)
            .environmentObject(audioManager)
            .environmentObject(settingsManager)
        #endif
    }

    // MARK: - Helpers

    private func ensureAtLeastOneSession() {
        if chatSessionsViewModel.chatSessions.isEmpty {
            chatSessionsViewModel.startNewSession()
        }
    }

    private func selectConversation(_ session: ChatSession) {
        chatSessionsViewModel.selectedSession = session
    }

    private func startNewConversation() {
        chatSessionsViewModel.startNewSession()
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
