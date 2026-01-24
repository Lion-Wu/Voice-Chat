//
//  AppEnvironment.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/16.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

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

    private var cancellables: Set<AnyCancellable> = []
    private var reachabilityTask: Task<Void, Never>?
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
        self.chatSessionsViewModel = chatSessionsViewModel ?? ChatSessionsViewModel()
        self.speechInputManager = speechInputManager ?? .shared
        self.errorCenter = errorCenter ?? .shared
        self.reachabilityMonitor = reachabilityMonitor ?? .shared
        self.voiceOverlayViewModel = VoiceChatOverlayViewModel(
            speechInputManager: self.speechInputManager,
            audioManager: self.audioManager,
            errorCenter: self.errorCenter,
            settingsManager: self.settingsManager,
            reachabilityMonitor: self.reachabilityMonitor
        )
#if os(macOS)
        self.realtimeVoiceWindowController = RealtimeVoiceWindowController(
            overlayViewModel: self.voiceOverlayViewModel,
            errorCenter: self.errorCenter
        )
#endif
        bindRealtimeVoiceLock()
    }

    /// Bootstraps the environment exactly once after SwiftData is available.
    func start(with context: ModelContext) {
        guard !didStart else { return }
        didStart = true

        bindModelContext(context)
        observeSettingsChanges()
        startReachabilityMonitoring()
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

    // MARK: - Private helpers

    private func observeSettingsChanges() {
        settingsManager.$chatSettings
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.chatSessionsViewModel.refreshChatConfigurationIfNeeded()
                self.kickReachabilityCheck()
            }
            .store(in: &cancellables)

        settingsManager.$serverSettings
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.kickReachabilityCheck()
            }
            .store(in: &cancellables)
    }

    private func startReachabilityMonitoring() {
        kickReachabilityCheck()
        reachabilityMonitor.startMonitoring(settings: settingsManager)
    }

    private func kickReachabilityCheck() {
        reachabilityTask?.cancel()
        reachabilityTask = Task { [settingsManager, reachabilityMonitor] in
            await reachabilityMonitor.checkAll(settings: settingsManager)
        }
    }

    private func bindRealtimeVoiceLock() {
        voiceOverlayViewModel.$isPresented
            .combineLatest(audioManager.$isRealtimeMode)
            .map { presented, realtime in presented || realtime }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                self?.chatSessionsViewModel.updateRealtimeVoiceLock(active)
            }
            .store(in: &cancellables)
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
