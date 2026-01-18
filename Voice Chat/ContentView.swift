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
    @EnvironmentObject var appEnvironment: AppEnvironment
    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var speechInputManager: SpeechInputManager
    @EnvironmentObject var errorCenter: AppErrorCenter
    @EnvironmentObject var voiceOverlayViewModel: VoiceChatOverlayViewModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        #if os(macOS)
        macContent
        #else
        iosContent
        #endif
    }

    // MARK: - Helpers

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
                        chatSessionsViewModel.selectedSession = conversation
                    },
                    onOpenSettings: { openSettingsWindow() }
                )
            } detail: {
                let activeSession = chatSessionsViewModel.selectedSession ?? chatSessionsViewModel.draftSession
                ChatView(viewModel: chatSessionsViewModel.viewModel(for: activeSession))
                    .id(activeSession.id)
            }
            .toolbar {
                ToolbarItem {
                    if !voiceOverlayViewModel.isPresented {
                        Button(action: { chatSessionsViewModel.startNewSession() }) {
                            Label("New Chat", systemImage: "plus")
                        }
                        .labelStyle(.iconOnly)
                        .help("New Chat")
                        .disabled(!chatSessionsViewModel.canStartNewSession)
                    }
                }
            }
        }
        .overlay(voiceOverlayLayer)
        .background {
#if os(macOS)
            WindowAccessor { window in
                appEnvironment.realtimeVoiceWindowController.registerMainWindow(window)
            }
#endif
        }
    }
#endif

#if os(iOS) || os(tvOS)
    @ViewBuilder
    var iosContent: some View {
        ZStack {
            AppBackgroundView()
            SideMenuContainerRepresentable()
                .environmentObject(chatSessionsViewModel)
                .environmentObject(audioManager)
                .environmentObject(settingsManager)
                .environmentObject(speechInputManager)
                .environmentObject(errorCenter)
                .ignoresSafeArea()
            voiceOverlayLayer
        }
    }
#endif

    @ViewBuilder
    private var voiceOverlayLayer: some View {
#if os(macOS)
        EmptyView()
#else
        if voiceOverlayViewModel.isPresented {
            RealtimeVoiceOverlayView(viewModel: voiceOverlayViewModel)
                .transition(.opacity.combined(with: .scale))
                .zIndex(2000)
        }
#endif
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let speechManager = SpeechInputManager()
        let chatSessions = ChatSessionsViewModel()
        let appEnvironment = AppEnvironment(
            audioManager: GlobalAudioManager.shared,
            settingsManager: SettingsManager.shared,
            chatSessionsViewModel: chatSessions,
            speechInputManager: speechManager,
            errorCenter: AppErrorCenter.shared
        )

        return ContentView()
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(appEnvironment)
            .environmentObject(appEnvironment.audioManager)
            .environmentObject(appEnvironment.settingsManager)
            .environmentObject(chatSessions)
            .environmentObject(speechManager)
            .environmentObject(AppErrorCenter.shared)
            .environmentObject(appEnvironment.voiceOverlayViewModel)
    }
}

#if os(macOS)
/// Resolves the hosting NSWindow so we can coordinate visibility changes.
private struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
#endif
