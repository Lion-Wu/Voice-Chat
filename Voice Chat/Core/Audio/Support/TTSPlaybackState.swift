//
//  TTSPlaybackState.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct TTSPlaybackState: Equatable, Sendable {
    let textSegmentCount: Int
    let audioChunkIsLoaded: [Bool]
    let chunkDurations: [TimeInterval]
    let skippedAudioChunkIndexes: Set<Int>
    let currentChunkIndex: Int
    let currentTime: TimeInterval
    let totalDuration: TimeInterval
    let endEpsilon: TimeInterval
    let isLoading: Bool
    let isRealtimeMode: Bool
    let realtimeFinalized: Bool
    let inFlightIndexes: Set<Int>
    let retryingIndexes: Set<Int>
    let pendingRealtimeIndexes: [Int]

    init(
        textSegmentCount: Int,
        audioChunkIsLoaded: [Bool],
        chunkDurations: [TimeInterval],
        skippedAudioChunkIndexes: Set<Int>,
        currentChunkIndex: Int = 0,
        currentTime: TimeInterval = 0,
        totalDuration: TimeInterval = 0,
        endEpsilon: TimeInterval = 0.03,
        isLoading: Bool = false,
        isRealtimeMode: Bool = false,
        realtimeFinalized: Bool = false,
        inFlightIndexes: Set<Int> = [],
        retryingIndexes: Set<Int> = [],
        pendingRealtimeIndexes: [Int] = []
    ) {
        self.textSegmentCount = max(0, textSegmentCount)
        self.audioChunkIsLoaded = audioChunkIsLoaded
        self.chunkDurations = chunkDurations
        self.skippedAudioChunkIndexes = skippedAudioChunkIndexes
        self.currentChunkIndex = currentChunkIndex
        self.currentTime = currentTime
        self.totalDuration = totalDuration
        self.endEpsilon = endEpsilon
        self.isLoading = isLoading
        self.isRealtimeMode = isRealtimeMode
        self.realtimeFinalized = realtimeFinalized
        self.inFlightIndexes = inFlightIndexes
        self.retryingIndexes = retryingIndexes
        self.pendingRealtimeIndexes = pendingRealtimeIndexes
    }

    var allChunksLoaded: Bool {
        audioChunkIsLoaded.indices.allSatisfy { index in
            audioChunkIsLoaded[index] || skippedAudioChunkIndexes.contains(index)
        }
    }

    var playbackFinished: Bool {
        if !isRealtimeMode,
           !audioChunkIsLoaded.isEmpty,
           allChunksLoaded,
           totalDuration <= endEpsilon,
           currentChunkIndex >= textSegmentCount {
            return true
        }
        return totalDuration > 0 && allChunksLoaded && currentTime >= max(0, totalDuration - endEpsilon)
    }

    var calculatedTotalDuration: TimeInterval {
        chunkDurations.reduce(0) { $0 + max(0, $1) }
    }

    var isPlaybackFullyLoaded: Bool {
        let hasTrackedAudioWork =
            textSegmentCount > 0 ||
            !audioChunkIsLoaded.isEmpty ||
            !inFlightIndexes.isEmpty ||
            !pendingRealtimeIndexes.isEmpty ||
            isLoading ||
            isRealtimeMode

        guard hasTrackedAudioWork else {
            return true
        }

        let hasMissingAudio = audioChunkIsLoaded.indices.contains { index in
            !audioChunkIsLoaded[index] && !skippedAudioChunkIndexes.contains(index)
        }
        let hasOutstandingRequests = !inFlightIndexes.isEmpty || !retryingIndexes.isEmpty

        if isRealtimeMode {
            return realtimeFinalized &&
                !hasMissingAudio &&
                !hasOutstandingRequests &&
                pendingRealtimeIndexes.isEmpty
        }

        if textSegmentCount == 0 && audioChunkIsLoaded.isEmpty {
            return !isLoading && !hasOutstandingRequests
        }

        let hasQueuedSegments = currentChunkIndex < textSegmentCount
        return !hasMissingAudio && !hasOutstandingRequests && !hasQueuedSegments
    }

    func findSegmentIndex(for time: TimeInterval) -> Int {
        if chunkDurations.isEmpty { return 0 }
        var cumulative: TimeInterval = 0
        for index in 0..<chunkDurations.count {
            let duration = max(0, chunkDurations[index])
            if duration == 0 {
                if time <= cumulative + 0.001 { return index }
            } else {
                if time < cumulative + duration { return index }
                cumulative += duration
            }
        }
        return max(0, chunkDurations.count - 1)
    }

    func startTime(forSegment index: Int) -> TimeInterval {
        guard index > 0, index <= chunkDurations.count else { return 0 }
        var sum: TimeInterval = 0
        for chunkIndex in 0..<index {
            sum += max(0, chunkDurations[chunkIndex])
        }
        return sum
    }
}
