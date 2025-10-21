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
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var speechInputManager: SpeechInputManager

#if os(macOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
#else
    @State private var showingSettings = false
#endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                onConversationTap: { conversation in
                    selectConversation(conversation)
                },
                onOpenSettings: openSettings
            )
        } detail: {
            if let selectedSession = chatSessionsViewModel.selectedSession {
                ChatView(chatSession: selectedSession)
                    .id(selectedSession.id)
            } else {
                Text(L10n.Content.noChatSelected)
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                    .onAppear {
                        ensureAtLeastOneSession()
                    }
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: startNewConversation) {
                    Image(systemName: "plus")
                }
                .help(L10n.Common.helpNewChat)
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
            .environmentObject(settingsViewModel)
            .environmentObject(speechInputManager)
            .onAppear {
                chatSessionsViewModel.attach(context: modelContext)
                settingsManager.attach(context: modelContext)
                ensureAtLeastOneSession()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(settingsManager)
                    .environmentObject(settingsViewModel)
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

    private func openSettings() {
#if os(macOS)
        AppUI.openSettingsWindow()
#else
        showingSettings = true
#endif
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(SettingsManager.shared)
            .environmentObject(SettingsViewModel())
            .environmentObject(ChatSessionsViewModel())
            .environmentObject(SpeechInputManager())
    }
}
