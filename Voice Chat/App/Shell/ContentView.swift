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

struct ChatSessionNavigationRoute: Hashable {
    let sessionID: UUID
    let searchQuery: String?

    init(sessionID: UUID, searchQuery: String? = nil) {
        self.sessionID = sessionID
        let trimmedQuery = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.searchQuery = trimmedQuery?.isEmpty == false ? trimmedQuery : nil
    }
}

struct ContentView: View {
    @EnvironmentObject var appEnvironment: AppEnvironment
    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var errorCenter: AppErrorCenter
    @EnvironmentObject var voiceOverlayViewModel: VoiceChatOverlayViewModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #if os(iOS) || os(tvOS)
    @State private var iosNavigationPath: [ChatSessionNavigationRoute] = []
    @State private var isIOSSettingsPresented = false
    #endif

    var body: some View {
        #if os(macOS)
        macContent
        #elseif os(visionOS)
        visionContent
        #else
        iosContent
        #endif
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
        NavigationStack(path: $iosNavigationPath) {
            SidebarView(
                onConversationTap: { conversation in
                    chatSessionsViewModel.selectedSession = conversation
                    let route = ChatSessionNavigationRoute(sessionID: conversation.id)
                    if iosNavigationPath.last != route {
                        iosNavigationPath.append(route)
                    }
                },
                onOpenSettings: {
                    isIOSSettingsPresented = true
                }
            )
            .navigationDestination(for: ChatSessionNavigationRoute.self) { route in
                let session = iosSession(with: route.sessionID)
                ChatView(viewModel: chatSessionsViewModel.viewModel(for: session))
                    .id(session.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: {
                                startNewIOSSession()
                            }) {
                                Label("New Chat", systemImage: "square.and.pencil")
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("New Chat")
                            .disabled(!chatSessionsViewModel.canStartNewSession)
                        }
                    }
                .onAppear {
                    selectIOSSession(with: route.sessionID, matchingSearchQuery: route.searchQuery)
                }
            }
        }
        .sheet(isPresented: $isIOSSettingsPresented) {
            SettingsView(settingsManager: settingsManager)
        }
        .overlay(voiceOverlayLayer)
    }

    private func iosSession(with sessionID: UUID) -> ChatSession {
        if sessionID == chatSessionsViewModel.draftSession.id {
            return chatSessionsViewModel.draftSession
        }
        return chatSessionsViewModel.chatSessions.first(where: { $0.id == sessionID })
            ?? chatSessionsViewModel.draftSession
    }

    private func selectIOSSession(with sessionID: UUID, matchingSearchQuery searchQuery: String?) {
        if sessionID == chatSessionsViewModel.draftSession.id {
            chatSessionsViewModel.selectedSession = chatSessionsViewModel.draftSession
        } else if let session = chatSessionsViewModel.chatSessions.first(where: { $0.id == sessionID }) {
            chatSessionsViewModel.selectSession(session, matchingSidebarQuery: searchQuery)
        }
    }

    private func startNewIOSSession() {
        guard chatSessionsViewModel.canStartNewSession else { return }
        chatSessionsViewModel.startNewSession()
        let draftID = chatSessionsViewModel.draftSession.id
        let route = ChatSessionNavigationRoute(sessionID: draftID)
        if iosNavigationPath != [route] {
            iosNavigationPath = [route]
        }
        AppHaptics.trigger(.selection)
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

#Preview {
    let speechManager = SpeechInputManager()
    let audioManager = GlobalAudioManager.shared
    let settingsManager = SettingsManager.shared
    let reachabilityMonitor = ServerReachabilityMonitor.shared
    let chatSessions = ChatSessionsViewModel(
        settingsManager: settingsManager,
        reachability: reachabilityMonitor,
        audioManager: audioManager
    )
    let appEnvironment = AppEnvironment(
        audioManager: audioManager,
        settingsManager: settingsManager,
        chatSessionsViewModel: chatSessions,
        speechInputManager: speechManager,
        errorCenter: AppErrorCenter.shared,
        reachabilityMonitor: reachabilityMonitor
    )

    ContentView()
        .modelContainer(for: [ChatSession.self, ChatMessage.self, ChatRequestContextMetadata.self, AppSettings.self], inMemory: true)
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
    let audioManager = GlobalAudioManager.shared
    let settingsManager = SettingsManager.shared
    let reachabilityMonitor = ServerReachabilityMonitor.shared
    let chatSessions = ChatSessionsViewModel(
        settingsManager: settingsManager,
        reachability: reachabilityMonitor,
        audioManager: audioManager
    )
    let appEnvironment = AppEnvironment(
        audioManager: audioManager,
        settingsManager: settingsManager,
        chatSessionsViewModel: chatSessions,
        speechInputManager: speechManager,
        errorCenter: AppErrorCenter.shared,
        reachabilityMonitor: reachabilityMonitor
    )

    appEnvironment.voiceOverlayViewModel.isPresented = true

    return ContentView()
        .modelContainer(for: [ChatSession.self, ChatMessage.self, ChatRequestContextMetadata.self, AppSettings.self], inMemory: true)
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
