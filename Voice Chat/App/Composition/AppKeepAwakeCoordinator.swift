//
//  AppKeepAwakeCoordinator.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/13.
//

import Combine
import Foundation

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppKeepAwakeCoordinator {
    private let chatSessionsViewModel: ChatSessionsViewModel
    private let audioManager: GlobalAudioManager
    private let voiceOverlayViewModel: VoiceChatOverlayViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var keepAwakeActivity: NSObjectProtocol?
    private var isKeepingAwake = false
    private var didStart = false

    init(
        chatSessionsViewModel: ChatSessionsViewModel,
        audioManager: GlobalAudioManager,
        voiceOverlayViewModel: VoiceChatOverlayViewModel
    ) {
        self.chatSessionsViewModel = chatSessionsViewModel
        self.audioManager = audioManager
        self.voiceOverlayViewModel = voiceOverlayViewModel
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        let textActive = chatSessionsViewModel.$hasActiveTextRequests
            .removeDuplicates()

        let audioActive = Publishers.CombineLatest4(
            audioManager.$isAudioPlaying,
            audioManager.$isLoading,
            audioManager.isBufferingPublisher.removeDuplicates(),
            audioManager.isRetryingPublisher.removeDuplicates()
        )
        .map { playing, loading, buffering, retrying in
            playing || loading || buffering || retrying
        }
        .removeDuplicates()

        let voiceActive = Publishers.CombineLatest3(
            voiceOverlayViewModel.$isPresented,
            voiceOverlayViewModel.$state,
            audioManager.$isRealtimeMode
        )
        .map { presented, state, realtime in
            let overlayOK: Bool
            if presented {
                if case .error = state {
                    overlayOK = false
                } else {
                    overlayOK = true
                }
            } else {
                overlayOK = false
            }
            return overlayOK || realtime
        }
        .removeDuplicates()

        Publishers.CombineLatest3(textActive, audioActive, voiceActive)
            .map { text, audio, voice in text || audio || voice }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                self?.applyKeepAwake(active)
            }
            .store(in: &cancellables)
    }

    private func applyKeepAwake(_ active: Bool) {
        guard active != isKeepingAwake else { return }
        isKeepingAwake = active

#if os(macOS)
        if active {
            if keepAwakeActivity == nil {
                keepAwakeActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                    reason: "Voice Chat active"
                )
            }
        } else if let activity = keepAwakeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            keepAwakeActivity = nil
        }
#elseif canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = active
#endif
    }
}
