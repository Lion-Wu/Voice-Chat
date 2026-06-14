//
//  AppRealtimeVoiceLockCoordinator.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/13.
//

import Combine
import Foundation

@MainActor
final class AppRealtimeVoiceLockCoordinator {
    private let voiceOverlayViewModel: VoiceChatOverlayViewModel
    private let audioManager: GlobalAudioManager
    private let chatSessionsViewModel: ChatSessionsViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var didStart = false

    init(
        voiceOverlayViewModel: VoiceChatOverlayViewModel,
        audioManager: GlobalAudioManager,
        chatSessionsViewModel: ChatSessionsViewModel
    ) {
        self.voiceOverlayViewModel = voiceOverlayViewModel
        self.audioManager = audioManager
        self.chatSessionsViewModel = chatSessionsViewModel
    }

    func start() {
        guard !didStart else { return }
        didStart = true

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
