//
//  VoiceWorkSnapshot.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct VoiceWorkSnapshot: Equatable, Sendable {
    static let idle = VoiceWorkSnapshot(
        isRealtimeMode: false,
        isAudioLoading: false,
        isAudioPlaying: false,
        isPlaybackRequested: false,
        hasAudioRequests: false,
        isChatLoading: false,
        isChatPriming: false
    )

    let isRealtimeMode: Bool
    let isAudioLoading: Bool
    let isAudioPlaying: Bool
    let isPlaybackRequested: Bool
    let hasAudioRequests: Bool
    let isChatLoading: Bool
    let isChatPriming: Bool

    var hasVoiceWork: Bool {
        isRealtimeMode || isAudioLoading || isAudioPlaying || hasAudioRequests
    }

    var blocksListeningStart: Bool {
        isPlaybackRequested || isAudioPlaying || isAudioLoading || isChatLoading || isChatPriming
    }

    var blocksAutoResume: Bool {
        isPlaybackRequested || isAudioPlaying || isAudioLoading
    }

    func loadingStallTimeout(defaultTimeout: TimeInterval, activeAudioRequestTimeout: TimeInterval) -> TimeInterval {
        hasAudioRequests ? activeAudioRequestTimeout : defaultTimeout
    }
}

extension VoiceWorkSnapshot {
    init(
        audio: AudioPlaybackSnapshot,
        isChatLoading: Bool,
        isChatPriming: Bool
    ) {
        self.init(
            isRealtimeMode: audio.isRealtimeMode,
            isAudioLoading: audio.isLoading,
            isAudioPlaying: audio.isAudioPlaying,
            isPlaybackRequested: audio.isPlaybackRequested,
            hasAudioRequests: audio.hasAudioRequests,
            isChatLoading: isChatLoading,
            isChatPriming: isChatPriming
        )
    }
}
