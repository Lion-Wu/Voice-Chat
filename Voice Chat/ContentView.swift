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
        // macOS: 继续用原有的 NavigationSplitView
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
                        if chatSessionsViewModel.chatSessions.isEmpty {
                            chatSessionsViewModel.startNewSession()
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(settingsManager)
        }
        .toolbar {
            ToolbarItem {
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
            if chatSessionsViewModel.chatSessions.isEmpty {
                chatSessionsViewModel.startNewSession()
            }
        }
        #else
        // iOS/iPadOS: 使用我们自定义的侧边栏容器
        SideMenuContainerRepresentable()
            .environmentObject(chatSessionsViewModel)
            .environmentObject(audioManager)
            .environmentObject(settingsManager)
        #endif
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
