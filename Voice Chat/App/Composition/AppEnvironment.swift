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
    private var boundModelContainer: ModelContainer?
    private var settingsModelContext: ModelContext?
    private var sessionsModelContext: ModelContext?
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

    /// Binds the only persistent container before the data-backed UI is published.
    func start(with container: ModelContainer) {
        guard bindModelContainer(container) else { return }

        guard !didStart else { return }
        didStart = true
        chatRuntimeCoordinator.start()
    }

    /// Reset Data replaces the container, so the same app-scoped environment
    /// must accept a new persistent container.
    @discardableResult
    func bindModelContainer(_ container: ModelContainer) -> Bool {
        guard boundModelContainer !== container else { return true }

        // Settings and conversations use isolated contexts backed by the same
        // container. A settings transaction can no longer flush or roll back a
        // throttled chat write, and separate app scenes cannot rebind each other.
        let settingsContext = ModelContext(container)
        guard settingsManager.attach(context: settingsContext) else { return false }

        let sessionsContext = ModelContext(container)
        guard chatSessionsViewModel.attach(context: sessionsContext) else {
            settingsManager.detachPersistentStore()
            return false
        }

        boundModelContainer = container
        settingsModelContext = settingsContext
        sessionsModelContext = sessionsContext
        chatSessionsViewModel.refreshChatConfigurationIfNeeded()
        return true
    }

    func quiescePersistentStore() {
        chatSessionsViewModel.detachPersistentStore()
        settingsManager.detachPersistentStore()
        sessionsModelContext = nil
        settingsModelContext = nil
        boundModelContainer = nil
    }

    func updatePersistenceMode(for scenePhase: ScenePhase) {
        let shouldForceImmediateSaves = scenePhase != .active
        chatSessionsViewModel.setImmediatePersistenceEnabled(shouldForceImmediateSaves)
    }

}
