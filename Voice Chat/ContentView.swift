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
    @EnvironmentObject var errorCenter: AppErrorCenter
    @EnvironmentObject var voiceOverlayViewModel: VoiceChatOverlayViewModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        #if os(macOS)
        macContent
        #elseif os(visionOS)
        visionContent
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

#if os(iOS) || os(tvOS) || os(visionOS)
    @ViewBuilder
    var iosContent: some View {
        ZStack {
            AppBackgroundView()
            SideMenuContainerRepresentable(speechInputManager: appEnvironment.speechInputManager)
                .environmentObject(chatSessionsViewModel)
                .environmentObject(audioManager)
                .environmentObject(settingsManager)
                .environmentObject(errorCenter)
                .ignoresSafeArea()
            voiceOverlayLayer
        }
    }
#endif

#if os(visionOS)
    @ViewBuilder
    var visionContent: some View {
        VisionRootView()
            .environmentObject(appEnvironment)
            .environmentObject(audioManager)
            .environmentObject(settingsManager)
            .environmentObject(chatSessionsViewModel)
            .environmentObject(errorCenter)
            .environmentObject(voiceOverlayViewModel)
    }
#endif

    @ViewBuilder
    private var voiceOverlayLayer: some View {
#if os(macOS)
        EmptyView()
#elseif os(visionOS)
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

#if os(visionOS)
private struct VisionRootView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var audioManager: GlobalAudioManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject private var errorCenter: AppErrorCenter
    @EnvironmentObject private var voiceOverlayViewModel: VoiceChatOverlayViewModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isShowingSettings = false

    private var activeSession: ChatSession {
        chatSessionsViewModel.selectedSession ?? chatSessionsViewModel.draftSession
    }

    var body: some View {
        ZStack {
            visionChatShell
                .opacity(voiceOverlayViewModel.isPresented ? 0 : 1)
                .allowsHitTesting(!voiceOverlayViewModel.isPresented)
                .accessibilityHidden(voiceOverlayViewModel.isPresented)

            if voiceOverlayViewModel.isPresented {
                VisionVoiceExperienceView(viewModel: voiceOverlayViewModel)
                    .environmentObject(errorCenter)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .frame(minWidth: 1220, idealWidth: 1480, minHeight: 820, idealHeight: 940)
        .background(AppBackgroundView())
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: voiceOverlayViewModel.isPresented)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settingsManager: settingsManager)
                .environmentObject(appEnvironment)
                .environmentObject(errorCenter)
                .presentationDetents([.medium, .large])
        }
    }

    private var visionChatShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                onConversationTap: { session in
                    chatSessionsViewModel.selectedSession = session
                },
                onOpenSettings: {
                    isShowingSettings = true
                }
            )
            .navigationSplitViewColumnWidth(min: 344, ideal: 392, max: 448)
        } detail: {
            ChatView(viewModel: chatSessionsViewModel.viewModel(for: activeSession))
                .id(activeSession.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button {
                            toggleSidebar()
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel("Toggle sidebar")
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            guard chatSessionsViewModel.canStartNewSession else { return }
                            chatSessionsViewModel.startNewSession()
                        } label: {
                            Label("New Chat", systemImage: "plus")
                        }
                        .disabled(!chatSessionsViewModel.canStartNewSession)
                    }
                }
        }
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewStyle(.balanced)
    }

    private func toggleSidebar() {
        switch columnVisibility {
        case .all, .doubleColumn:
            columnVisibility = .detailOnly
        default:
            columnVisibility = .all
        }
    }
}

private struct VisionVoiceExperienceView: View {
    @ObservedObject var viewModel: VoiceChatOverlayViewModel

    var body: some View {
        RealtimeVoiceOverlayView(viewModel: viewModel, displayStyle: .visionScene)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif

#Preview {
    let speechManager = SpeechInputManager()
    let chatSessions = ChatSessionsViewModel()
    let appEnvironment = AppEnvironment(
        audioManager: GlobalAudioManager.shared,
        settingsManager: SettingsManager.shared,
        chatSessionsViewModel: chatSessions,
        speechInputManager: speechManager,
        errorCenter: AppErrorCenter.shared
    )

    ContentView()
        .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
        .environmentObject(appEnvironment)
        .environmentObject(appEnvironment.audioManager)
        .environmentObject(appEnvironment.settingsManager)
        .environmentObject(chatSessions)
        .environmentObject(speechManager)
        .environmentObject(AppErrorCenter.shared)
        .environmentObject(appEnvironment.voiceOverlayViewModel)
}

#if os(visionOS)
#Preview("Vision Voice Session") {
    let speechManager = SpeechInputManager()
    let chatSessions = ChatSessionsViewModel()
    let appEnvironment = AppEnvironment(
        audioManager: GlobalAudioManager.shared,
        settingsManager: SettingsManager.shared,
        chatSessionsViewModel: chatSessions,
        speechInputManager: speechManager,
        errorCenter: AppErrorCenter.shared
    )

    appEnvironment.voiceOverlayViewModel.isPresented = true

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
#endif

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
