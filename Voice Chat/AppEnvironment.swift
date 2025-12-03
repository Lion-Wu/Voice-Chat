//
//  AppEnvironment.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/16.
//

import Foundation
import SwiftUI
import SwiftData

/// Central place to build and share app-scoped dependencies.
@MainActor
final class AppEnvironment: ObservableObject {
    let audioManager: GlobalAudioManager
    let settingsManager: SettingsManager
    let chatSessionsViewModel: ChatSessionsViewModel
    let speechInputManager: SpeechInputManager
    let errorCenter: AppErrorCenter
    let voiceOverlayViewModel: VoiceChatOverlayViewModel
    let reachabilityMonitor: ServerReachabilityMonitor

    private var didBindModelContext = false

    init(
        audioManager: GlobalAudioManager? = nil,
        settingsManager: SettingsManager? = nil,
        chatSessionsViewModel: ChatSessionsViewModel? = nil,
        speechInputManager: SpeechInputManager? = nil,
        errorCenter: AppErrorCenter? = nil,
        reachabilityMonitor: ServerReachabilityMonitor? = nil
    ) {
        // Resolve defaults inside the main-actor initializer to avoid crossing actor boundaries
        // in Swift 6 default argument evaluation.
        self.audioManager = audioManager ?? .shared
        self.settingsManager = settingsManager ?? .shared
        self.chatSessionsViewModel = chatSessionsViewModel ?? ChatSessionsViewModel()
        self.speechInputManager = speechInputManager ?? .shared
        self.errorCenter = errorCenter ?? .shared
        self.reachabilityMonitor = reachabilityMonitor ?? .shared
        self.voiceOverlayViewModel = VoiceChatOverlayViewModel(
            speechInputManager: self.speechInputManager,
            audioManager: self.audioManager,
            errorCenter: self.errorCenter
        )
    }

    /// Bind the SwiftData model context once and hydrate singletons before UI usage.
    func bindModelContext(_ context: ModelContext) {
        guard !didBindModelContext else { return }
        didBindModelContext = true

        settingsManager.attach(context: context)
        chatSessionsViewModel.attach(context: context)
        chatSessionsViewModel.refreshChatConfigurationIfNeeded()

        Task { [settingsManager] in
            await settingsManager.applyPresetOnLaunchIfNeeded()
        }
    }
}

/// Lightweight helper view to inject the model context into the shared environment once.
struct ModelContextBinder: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appEnvironment: AppEnvironment

    var body: some View {
        Color.clear
            .task {
                appEnvironment.bindModelContext(modelContext)
            }
    }
}
