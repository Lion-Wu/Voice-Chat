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

    @StateObject private var reachabilityMonitor = ServerReachabilityMonitor.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var voiceOverlayViewModel = VoiceChatOverlayViewModel(
        speechInputManager: SpeechInputManager.shared,
        audioManager: GlobalAudioManager.shared,
        errorCenter: AppErrorCenter.shared
    )

    var body: some View {
        #if os(macOS)
        macContent
            .environmentObject(voiceOverlayViewModel)
        #else
        iosContent
            .environmentObject(voiceOverlayViewModel)
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

    private func runConnectivityChecks() {
        Task {
            await reachabilityMonitor.checkAll(settings: settingsManager)
        }
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
                    .onAppear {
                        ensureAtLeastOneSession()
                    }
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
                chatSessionsViewModel.attach(context: modelContext)
                settingsManager.attach(context: modelContext)
                ensureAtLeastOneSession()
                runConnectivityChecks()
                reachabilityMonitor.startMonitoring(settings: settingsManager)
            }
            .onChange(of: settingsManager.serverSettings.serverAddress) { _, _ in
                runConnectivityChecks()
                reachabilityMonitor.startMonitoring(settings: settingsManager)
            }
            .onChange(of: settingsManager.chatSettings.apiURL) { _, _ in
                runConnectivityChecks()
                reachabilityMonitor.startMonitoring(settings: settingsManager)
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
                chatSessionsViewModel.attach(context: modelContext)
                settingsManager.attach(context: modelContext)
                ensureAtLeastOneSession()
                runConnectivityChecks()
                reachabilityMonitor.startMonitoring(settings: settingsManager)
            }
            .onChange(of: settingsManager.serverSettings.serverAddress) { _, _ in
                runConnectivityChecks()
                reachabilityMonitor.startMonitoring(settings: settingsManager)
            }
            .onChange(of: settingsManager.chatSettings.apiURL) { _, _ in
                runConnectivityChecks()
                reachabilityMonitor.startMonitoring(settings: settingsManager)
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
        ContentView()
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(SettingsManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .environmentObject(SpeechInputManager())
            .environmentObject(AppErrorCenter.shared)
    }
}
