//
//  ContentView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var speechInputManager: SpeechInputManager   // ★ 新增

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
        .onAppear {
            chatSessionsViewModel.attach(context: modelContext)
            settingsManager.attach(context: modelContext)
            ensureAtLeastOneSession()
        }
        #else
        SideMenuContainerRepresentable()
            .environmentObject(chatSessionsViewModel)
            .environmentObject(audioManager)
            .environmentObject(settingsManager)
            .environmentObject(speechInputManager) // ★ 传入 iOS 容器
            .onAppear {
                chatSessionsViewModel.attach(context: modelContext)
                settingsManager.attach(context: modelContext)
                ensureAtLeastOneSession()
            }
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
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(SettingsManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .environmentObject(SpeechInputManager()) // ★ 新增
    }
}
