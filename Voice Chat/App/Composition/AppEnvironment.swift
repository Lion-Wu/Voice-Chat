//
//  AppEnvironment.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/16.
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
private final class SettingsHapticFeedbackPolicy: HapticFeedbackPolicy {
    private let settingsManager: SettingsManager

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    var isHapticFeedbackEnabled: Bool {
        settingsManager.hapticFeedbackEnabled
    }
}

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
#if os(macOS)
    let realtimeVoiceWindowController: RealtimeVoiceWindowController
#endif

    private let chatRuntimeCoordinator: AppChatRuntimeCoordinator
    private let realtimeVoiceLockCoordinator: AppRealtimeVoiceLockCoordinator
    private let keepAwakeCoordinator: AppKeepAwakeCoordinator
    private var didBindModelContext = false
    private var didStart = false

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
        self.speechInputManager = speechInputManager ?? .shared
        self.errorCenter = errorCenter ?? .shared
        self.reachabilityMonitor = reachabilityMonitor ?? .shared
        self.chatSessionsViewModel = chatSessionsViewModel ?? ChatSessionsViewModel(
            settingsManager: self.settingsManager,
            reachability: self.reachabilityMonitor,
            audioManager: self.audioManager
        )
        AppHaptics.configure(
            feedbackPolicy: SettingsHapticFeedbackPolicy(settingsManager: self.settingsManager)
        )
        self.voiceOverlayViewModel = VoiceChatOverlayViewModel(
            speechInputManager: self.speechInputManager,
            audioManager: self.audioManager,
            errorCenter: self.errorCenter,
            settingsManager: self.settingsManager,
            reachabilityMonitor: self.reachabilityMonitor
        )
        self.chatRuntimeCoordinator = AppChatRuntimeCoordinator(
            settingsManager: self.settingsManager,
            chatSessionsViewModel: self.chatSessionsViewModel,
            reachabilityMonitor: self.reachabilityMonitor
        )
        self.realtimeVoiceLockCoordinator = AppRealtimeVoiceLockCoordinator(
            voiceOverlayViewModel: self.voiceOverlayViewModel,
            audioManager: self.audioManager,
            chatSessionsViewModel: self.chatSessionsViewModel
        )
        self.keepAwakeCoordinator = AppKeepAwakeCoordinator(
            chatSessionsViewModel: self.chatSessionsViewModel,
            audioManager: self.audioManager,
            voiceOverlayViewModel: self.voiceOverlayViewModel
        )
#if os(macOS)
        self.realtimeVoiceWindowController = RealtimeVoiceWindowController(
            overlayViewModel: self.voiceOverlayViewModel,
            errorCenter: self.errorCenter
        )
#endif
        realtimeVoiceLockCoordinator.start()
        keepAwakeCoordinator.start()
    }

    /// Bootstraps the environment exactly once after SwiftData is available.
    func start(with context: ModelContext) {
        guard !didStart else { return }
        didStart = true

        bindModelContext(context)
        chatRuntimeCoordinator.start()
    }

    /// Bind the SwiftData model context once and hydrate singletons before UI usage.
    func bindModelContext(_ context: ModelContext) {
        guard !didBindModelContext else { return }
        didBindModelContext = true

        settingsManager.attach(context: context)
        chatSessionsViewModel.attach(context: context)
        chatSessionsViewModel.refreshChatConfigurationIfNeeded()
    }

    func updatePersistenceMode(for scenePhase: ScenePhase) {
        let shouldForceImmediateSaves = scenePhase != .active
        chatSessionsViewModel.setImmediatePersistenceEnabled(shouldForceImmediateSaves)
    }

}

/// Lightweight helper view to inject the model context into the shared environment once.
struct ModelContextBinder: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appEnvironment: AppEnvironment

    var body: some View {
        Color.clear
            .task {
                appEnvironment.start(with: modelContext)
            }
    }
}
