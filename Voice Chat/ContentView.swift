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
    @EnvironmentObject var errorCenter: AppErrorCenter
    @EnvironmentObject var voiceOverlayViewModel: VoiceChatOverlayViewModel

    @StateObject private var appViewModel = AppViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        #if os(macOS)
        macContent
        #else
        iosContent
        #endif
    }

    // MARK: - Helpers

    private func prepareOnAppear() {
        appViewModel.handleAppear(
            context: modelContext,
            settingsManager: settingsManager,
            chatSessionsViewModel: chatSessionsViewModel
        )
    }

    private func handleServerChange() {
        appViewModel.handleServerChange(
            settingsManager: settingsManager,
            chatSessionsViewModel: chatSessionsViewModel
        )
    }

    private func selectConversation(_ session: ChatSession) {
        appViewModel.selectConversation(session, store: chatSessionsViewModel)
    }

    private func startNewConversation() {
        appViewModel.startNewConversation(store: chatSessionsViewModel)
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

private extension ContentView {
#if os(macOS)
    @ViewBuilder
    var macContent: some View {
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
                }
            }
            .toolbar {
                ToolbarItem {
                    if !voiceOverlayViewModel.isPresented {
                        Button(action: startNewConversation) {
                            Label("New Chat", systemImage: "plus")
                        }
                        .labelStyle(.iconOnly)
                        .help("New Chat")
                        .disabled(!chatSessionsViewModel.canStartNewSession)
                    }
                }
            }
            .onAppear {
                prepareOnAppear()
            }
            .onChange(of: settingsManager.serverSettings.serverAddress) { _, _ in
                handleServerChange()
            }
            .onChange(of: settingsManager.chatSettings.apiURL) { _, _ in
                handleServerChange()
            }
            .onChange(of: settingsManager.chatSettings.selectedModel) { _, _ in
                handleServerChange()
            }
        }
        .overlay(voiceOverlayLayer)
    }
#endif

#if os(iOS) || os(tvOS)
    @ViewBuilder
    var iosContent: some View {
        SideMenuContainerRepresentable()
            .environmentObject(chatSessionsViewModel)
            .environmentObject(audioManager)
            .environmentObject(settingsManager)
            .environmentObject(speechInputManager)
            .environmentObject(errorCenter)
            .overlay(voiceOverlayLayer)
            .onAppear {
                prepareOnAppear()
            }
            .onChange(of: settingsManager.serverSettings.serverAddress) { _, _ in
                handleServerChange()
            }
            .onChange(of: settingsManager.chatSettings.apiURL) { _, _ in
                handleServerChange()
            }
            .onChange(of: settingsManager.chatSettings.selectedModel) { _, _ in
                handleServerChange()
            }
    }
#endif

    @ViewBuilder
    private var voiceOverlayLayer: some View {
        if voiceOverlayViewModel.isPresented {
            RealtimeVoiceOverlayView(viewModel: voiceOverlayViewModel)
                .transition(.opacity.combined(with: .scale))
                .zIndex(2000)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let speechManager = SpeechInputManager()
        let overlayVM = VoiceChatOverlayViewModel(
            speechInputManager: speechManager,
            audioManager: GlobalAudioManager.shared,
            errorCenter: AppErrorCenter.shared
        )

        return ContentView()
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(SettingsManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .environmentObject(speechManager)
            .environmentObject(AppErrorCenter.shared)
            .environmentObject(overlayVM)
    }
}
