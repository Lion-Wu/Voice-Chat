//
//  VoiceWorkSnapshot.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

enum VoiceWorkPresentationPhase: Equatable, Sendable {
    case idle
    case loading
    case speaking
}

struct VoiceWorkSnapshot: Equatable, Sendable {
    static let idle = VoiceWorkSnapshot(
        isRealtimeMode: false,
        isAudioLoading: false,
        isAudioPlaying: false,
        isPlaybackRequested: false,
        hasAudioRequests: false,
        isChatLoading: false,
        isChatPriming: false,
        isWaitingForToolAuthorization: false
    )

    let isRealtimeMode: Bool
    let isAudioLoading: Bool
    let isAudioPlaying: Bool
    let isPlaybackRequested: Bool
    let hasAudioRequests: Bool
    let isChatLoading: Bool
    let isChatPriming: Bool
    let isWaitingForToolAuthorization: Bool

    init(
        isRealtimeMode: Bool,
        isAudioLoading: Bool,
        isAudioPlaying: Bool,
        isPlaybackRequested: Bool,
        hasAudioRequests: Bool,
        isChatLoading: Bool,
        isChatPriming: Bool,
        isWaitingForToolAuthorization: Bool = false
    ) {
        self.isRealtimeMode = isRealtimeMode
        self.isAudioLoading = isAudioLoading
        self.isAudioPlaying = isAudioPlaying
        self.isPlaybackRequested = isPlaybackRequested
        self.hasAudioRequests = hasAudioRequests
        self.isChatLoading = isChatLoading
        self.isChatPriming = isChatPriming
        self.isWaitingForToolAuthorization = isWaitingForToolAuthorization
    }

    var hasVoiceWork: Bool {
        isRealtimeMode || isPlaybackRequested || isAudioLoading || isAudioPlaying || hasAudioRequests
    }

    var hasActiveVoiceWork: Bool {
        isPlaybackRequested || isAudioLoading || isAudioPlaying || hasAudioRequests
    }

    var presentationPhase: VoiceWorkPresentationPhase {
        if isAudioPlaying {
            return .speaking
        }
        if isChatLoading ||
            isChatPriming ||
            isPlaybackRequested ||
            isAudioLoading ||
            hasAudioRequests {
            return .loading
        }
        return .idle
    }

    var blocksListeningStart: Bool {
        isPlaybackRequested ||
            isAudioPlaying ||
            isAudioLoading ||
            hasAudioRequests ||
            isChatLoading ||
            isChatPriming
    }

    var blocksAutoResume: Bool {
        isPlaybackRequested || isAudioPlaying || isAudioLoading || hasAudioRequests
    }

    func loadingStallTimeout(defaultTimeout: TimeInterval, activeAudioRequestTimeout: TimeInterval) -> TimeInterval {
        guard !isWaitingForToolAuthorization else { return .infinity }
        return hasAudioRequests ? activeAudioRequestTimeout : defaultTimeout
    }
}

extension VoiceWorkSnapshot {
    init(
        audio: AudioPlaybackSnapshot,
        isChatLoading: Bool,
        isChatPriming: Bool,
        isWaitingForToolAuthorization: Bool = false
    ) {
        self.init(
            isRealtimeMode: audio.isRealtimeMode,
            isAudioLoading: audio.isLoading,
            isAudioPlaying: audio.isAudioPlaying,
            isPlaybackRequested: audio.isPlaybackRequested,
            hasAudioRequests: audio.hasAudioRequests,
            isChatLoading: isChatLoading,
            isChatPriming: isChatPriming,
            isWaitingForToolAuthorization: isWaitingForToolAuthorization
        )
    }
}
