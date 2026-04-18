//
//  VisionRootView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

#if os(visionOS)
import SwiftUI

struct VisionRootView: View {
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
