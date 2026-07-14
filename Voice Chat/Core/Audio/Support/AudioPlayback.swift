//
//  AudioPlayback.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import AVFoundation

@MainActor
extension GlobalAudioManager {
    private func playbackStateSnapshot() -> TTSPlaybackState {
        TTSPlaybackState(
            textSegmentCount: textSegments.count,
            audioChunkIsLoaded: audioChunks.map { $0 != nil },
            chunkDurations: chunkDurations,
            skippedAudioChunkIndexes: skippedAudioChunkIndexes,
            currentChunkIndex: currentChunkIndex,
            currentTime: currentTime,
            totalDuration: totalDuration,
            endEpsilon: endEpsilon,
            isRealtimeMode: isRealtimeMode,
            realtimeFinalized: realtimeFinalized
        )
    }

    // MARK: - Segment Time Helpers
    func findSegmentIndex(for time: TimeInterval) -> Int {
        playbackStateSnapshot().findSegmentIndex(for: time)
    }

    func startTime(forSegment idx: Int) -> TimeInterval {
        playbackStateSnapshot().startTime(forSegment: idx)
    }

    func allChunksLoaded() -> Bool {
        playbackStateSnapshot().allChunksLoaded
    }

    func playbackFinished() -> Bool {
        playbackStateSnapshot().playbackFinished
    }

    func playbackFinished(at playbackTime: TimeInterval) -> Bool {
        playbackStateSnapshot().playbackFinished(at: playbackTime)
    }

    func recalcTotalDuration() {
        totalDuration = playbackStateSnapshot().calculatedTotalDuration
    }

    // MARK: - Finish
    func finishPlayback() {
        currentPlayingIndex = max(0, audioChunks.count - 1)
        currentTime = max(currentTime, totalDuration)
        isPlaybackRequested = false
        isAudioPlaying = false
        isBuffering = false
        isSeeking = false
        seekTime = nil

        audioPlayer?.stop()
        audioPlayer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil

        stopAudioTimer()
        stopStallWatchdog()
    }

    // MARK: - Prepare/Play
    func prepareNextAudioChunk(at index: Int) {
        var target = index
        while skippedAudioChunkIndexes.contains(target) {
            target += 1
        }
        guard let chunkOpt = audioChunks[safe: target], let data = chunkOpt else { return }
        if let p = try? AVAudioPlayer(data: data) {
            p.delegate = self
            p.prepareToPlay()
            nextAudioPlayer = p
        }
    }

    @discardableResult
    func playAudioChunk(at index: Int, fromTime t: TimeInterval? = nil, shouldPlay: Bool = true) -> Bool {
        guard index >= 0, index < audioChunks.count else {
            if !shouldPlay { isPlaybackRequested = false }
            isBuffering = false
            return false
        }
        if skippedAudioChunkIndexes.contains(index) {
            return advancePlaybackPastSkippedChunk(
                from: index,
                requestedGlobalTime: t,
                shouldPlay: shouldPlay
            )
        }
        guard let chunkOpt = audioChunks[safe: index], let data = chunkOpt else {
            isBuffering = shouldPlay
            stopAudioTimer()
            startStallWatchdog()
            isPlaybackRequested = shouldPlay
            isAudioPlaying = false
            if isRealtimeMode { isLoading = shouldPlay }
            return false
        }

        do {
            if playbackFinished() {
                finishPlayback()
                return false
            }

            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.prepareToPlay()
            audioPlayer?.stop()
            audioPlayer = p

            let segStart = startTime(forSegment: index)

            let localTime: TimeInterval
            if let global = t {
                let mapped = max(0, global - segStart)
                localTime = min(max(0, mapped), max(0, p.duration))
            } else {
                localTime = 0
            }

            let atSegmentEnd = localTime >= max(0, p.duration - endEpsilon)
            let atGlobalEnd = playbackFinished(at: segStart + localTime)
            if atSegmentEnd && atGlobalEnd {
                finishPlayback()
                return false
            }

            p.currentTime = localTime

            currentPlayingIndex = index
            isBuffering = false
            isSeeking = false

            if shouldPlay {
                isPlaybackRequested = true
                if playbackFinished(at: segStart + p.currentTime) {
                    finishPlayback()
                    return false
                }
                let didPlay = p.play() || p.play()
                guard didPlay else {
                    isBuffering = true
                    isAudioPlaying = false
                    if isRealtimeMode { isLoading = true }
                    startStallWatchdog()
                    return false
                }
                startAudioTimer()
                startStallWatchdog()
                isAudioPlaying = true
                if isRealtimeMode { isLoading = false }
            } else {
                isPlaybackRequested = false
                isAudioPlaying = false
                stopAudioTimer()
                startStallWatchdog()
            }

            prepareNextAudioChunk(at: index + 1)
            return true
        } catch {
            let message = String(format: NSLocalizedString("Failed to start audio playback: %@", comment: "Shown when AVAudioPlayer fails to start"), error.localizedDescription)
            self.surfaceTTSIssue(message, autoDismiss: 12)
            isBuffering = true
            startStallWatchdog()
            isPlaybackRequested = shouldPlay
            isAudioPlaying = false
            if isRealtimeMode {
                isLoading = shouldPlay
            }
            return false
        }
    }

    private func advancePlaybackPastSkippedChunk(
        from index: Int,
        requestedGlobalTime: TimeInterval?,
        shouldPlay: Bool
    ) -> Bool {
        var nextIndex = index + 1
        while nextIndex < audioChunks.count, skippedAudioChunkIndexes.contains(nextIndex) {
            nextIndex += 1
        }

        audioPlayer?.stop()
        audioPlayer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil
        stopAudioTimer()

        guard nextIndex < audioChunks.count else {
            currentPlayingIndex = min(audioChunks.count, max(0, index + 1))
            isAudioPlaying = false
            isPlaybackRequested = shouldPlay

            if isRealtimeMode {
                isBuffering = shouldPlay
                isLoading = shouldPlay
                startStallWatchdog()
                return false
            }

            if allChunksLoaded() {
                currentTime = totalDuration
                finishPlayback()
                return false
            }

            isBuffering = shouldPlay
            if shouldPlay {
                startStallWatchdog()
            } else {
                stopStallWatchdog()
            }
            return false
        }

        currentPlayingIndex = nextIndex
        let nextStart = startTime(forSegment: nextIndex)

        if let chunkOpt = audioChunks[safe: nextIndex], chunkOpt != nil {
            return playAudioChunk(
                at: nextIndex,
                fromTime: max(requestedGlobalTime ?? nextStart, nextStart),
                shouldPlay: shouldPlay
            )
        }

        currentTime = max(currentTime, nextStart)
        isBuffering = shouldPlay
        isPlaybackRequested = shouldPlay
        isAudioPlaying = false
        if isRealtimeMode { isLoading = shouldPlay }
        startStallWatchdog()
        return false
    }
}
