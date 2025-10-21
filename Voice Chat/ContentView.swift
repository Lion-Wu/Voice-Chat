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
    @EnvironmentObject var speechInputManager: SpeechInputManager

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
#if !os(macOS)
    @State private var showingSettings = false
#endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                onConversationTap: { conversation in
                    selectConversation(conversation)
                },
                onOpenSettings: { openSettings() }
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
        .toolbar {
            ToolbarItem {
                Button(action: startNewConversation) {
                    Image(systemName: "plus")
                }
                .help("New Chat")
                .disabled(!chatSessionsViewModel.canStartNewSession)
            }
        }
        .onAppear(perform: bindContextIfNeeded)
        #else
        SideMenuContainerRepresentable()
            .environmentObject(chatSessionsViewModel)
            .environmentObject(audioManager)
            .environmentObject(settingsManager)
            .environmentObject(speechInputManager)
            .onAppear(perform: bindContextIfNeeded)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(settingsManager)
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
        MacSettingsPresenter.present()
#else
        showingSettings = true
#endif
    }

    private func bindContextIfNeeded() {
        chatSessionsViewModel.attach(context: modelContext)
        settingsManager.attach(context: modelContext)
        ensureAtLeastOneSession()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(SettingsManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .environmentObject(SpeechInputManager())
    }
}
