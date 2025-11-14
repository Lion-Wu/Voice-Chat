//
//  ContentView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var speechInputManager: SpeechInputManager

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        #if os(macOS)
        ZStack {
            AppBackgroundView()

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(
                    onConversationTap: { conversation in
                        selectConversation(conversation)
                    },
                    onOpenSettings: { openSettingsWindow() }
                )
            } detail: {
                if let selectedSession = chatSessionsViewModel.selectedSession {
                    ChatView(viewModel: chatSessionsViewModel.viewModel(for: selectedSession))
                        .id(selectedSession.id)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("Select or start a chat")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        ensureAtLeastOneSession()
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button(action: startNewConversation) {
                        Label("New Chat", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .help("New Chat")
                    .disabled(!chatSessionsViewModel.canStartNewSession)
                }
            }
            .onAppear {
                chatSessionsViewModel.attach(context: modelContext)
                settingsManager.attach(context: modelContext)
                ensureAtLeastOneSession()
            }
        }
        #else
        SideMenuContainerRepresentable()
            .environmentObject(chatSessionsViewModel)
            .environmentObject(audioManager)
            .environmentObject(settingsManager)
            .environmentObject(speechInputManager)
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

    #if os(macOS)
    private func openSettingsWindow() {
        guard let app = NSApp else { return }
        app.activate(ignoringOtherApps: true)

        let selectors = ["showSettingsWindow:", "showPreferencesWindow:"]
        for name in selectors {
            let selector = Selector(name)
            if app.responds(to: selector) {
                app.sendAction(selector, to: nil, from: nil)
                break
            }
        }
    }
    #endif
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
