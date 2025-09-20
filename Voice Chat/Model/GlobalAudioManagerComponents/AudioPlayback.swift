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

    // MARK: - Segment Time Helpers
    func findSegmentIndex(for time: TimeInterval) -> Int {
        if chunkDurations.isEmpty { return 0 }
        var cum: TimeInterval = 0
        for i in 0..<chunkDurations.count {
            let dur = max(0, chunkDurations[i])
            if dur == 0 {
                if time <= cum + 0.001 { return i }
            } else {
                if time < cum + dur { return i }
                cum += dur
            }
        }
        return max(0, chunkDurations.count - 1)
    }

    func startTime(forSegment idx: Int) -> TimeInterval {
        guard idx > 0, idx <= chunkDurations.count else { return 0 }
        var sum: TimeInterval = 0
        for i in 0..<idx {
            sum += max(0, chunkDurations[i])
        }
        return sum
    }

    func allChunksLoaded() -> Bool {
        !audioChunks.contains(where: { $0 == nil })
    }

    func playbackFinished() -> Bool {
        totalDuration > 0 && allChunksLoaded() && currentTime >= max(0, totalDuration - endEpsilon)
    }

    func recalcTotalDuration() {
        totalDuration = chunkDurations.reduce(0) { $0 + max(0, $1) }
    }

    // MARK: - Finish
    func finishPlayback() {
        currentPlayingIndex = max(0, audioChunks.count - 1)
        currentTime = max(currentTime, totalDuration)
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
        guard let chunkOpt = audioChunks[safe: index], let data = chunkOpt else { return }
        if let p = try? AVAudioPlayer(data: data) {
            p.delegate = self
            p.prepareToPlay()
            nextAudioPlayer = p
        }
    }

    @discardableResult
    func playAudioChunk(at index: Int, fromTime t: TimeInterval? = nil, shouldPlay: Bool = true) -> Bool {
        guard index >= 0, index < audioChunks.count else {
            isBuffering = false
            return false
        }
        guard let chunkOpt = audioChunks[safe: index], let data = chunkOpt else {
            isBuffering = true
            stopAudioTimer()
            startStallWatchdog()
            if isRealtimeMode {
                isLoading = true
                isAudioPlaying = false
            }
            return false
        }

        do {
            if playbackFinished() || (allChunksLoaded() && currentTime >= totalDuration - endEpsilon) {
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
            let atGlobalEnd = allChunksLoaded() && (segStart + localTime) >= (totalDuration - endEpsilon)
            if atSegmentEnd && atGlobalEnd {
                finishPlayback()
                return false
            }

            p.currentTime = localTime

            currentPlayingIndex = index
            isBuffering = false
            isSeeking = false

            if shouldPlay {
                if allChunksLoaded() && (segStart + p.currentTime) >= (totalDuration - endEpsilon) {
                    finishPlayback()
                    return false
                }
                let didPlay = p.play()
                if !didPlay { _ = p.play() }
                startAudioTimer()
                startStallWatchdog()
                isAudioPlaying = true
                if isRealtimeMode { isLoading = false }
            } else {
                stopAudioTimer()
                startStallWatchdog()
            }

            prepareNextAudioChunk(at: index + 1)
            return true
        } catch {
            self.errorMessage = "Failed to start audio playback: \(error.localizedDescription)"
            isBuffering = true
            startStallWatchdog()
            if isRealtimeMode {
                isLoading = true
                isAudioPlaying = false
            }
            return false
        }
    }
}
