//
//  AudioPlaybackSnapshot.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct AudioPlaybackSnapshot: Equatable, Sendable {
    let isRealtimeMode: Bool
    let isLoading: Bool
    let isAudioPlaying: Bool
    let isPlaybackRequested: Bool
    let hasAudioRequests: Bool
    let hasLoadedAudioChunk: Bool
    let hasPlayableAudioRemaining: Bool
    let hasSeekableAudio: Bool

    var hasVoiceWork: Bool {
        isRealtimeMode || isLoading || isAudioPlaying || hasAudioRequests
    }
}

extension GlobalAudioManager {
    var audioPlaybackSnapshot: AudioPlaybackSnapshot {
        AudioPlaybackSnapshot(
            isRealtimeMode: isRealtimeMode,
            isLoading: isLoading,
            isAudioPlaying: isAudioPlaying,
            isPlaybackRequested: isPlaybackRequested,
            hasAudioRequests: hasPendingTTSSynthesisWork(),
            hasLoadedAudioChunk: audioChunks.contains { $0 != nil },
            hasPlayableAudioRemaining: audioChunks.indices.contains { index in
                guard index >= currentPlayingIndex,
                      audioChunks[index] != nil else { return false }
                if index > currentPlayingIndex { return true }
                let segmentEnd = startTime(forSegment: index) + (chunkDurations[safe: index] ?? 0)
                return isAudioPlaying || currentTime < max(0, segmentEnd - endEpsilon)
            },
            hasSeekableAudio: totalDuration > 0.0005 || chunkDurations.contains { $0 > 0.0005 }
        )
    }
}
