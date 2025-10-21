//
//  GlobalAudioManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation
import AVFoundation
import Combine
import NaturalLanguage
import SwiftUI

@MainActor
final class GlobalAudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = GlobalAudioManager()

    // MARK: - Public State
    @Published var isShowingAudioPlayer: Bool = false
    @Published var isAudioPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var isLoading: Bool = false
    @Published var isBuffering: Bool = false
    @Published var errorMessage: String?

    // Output level (0...1) drives the realtime overlay pulse.
    @Published var outputLevel: Float = 0

    // MARK: - Players & Timers
    var audioPlayer: AVAudioPlayer?
    var nextAudioPlayer: AVAudioPlayer?
    var audioTimer: Timer?

    // Watchdog
    var stallWatchdog: Timer?
    var lastObservedPlaybackTime: TimeInterval = 0
    var lastProgressTimestamp: Date = .init()

    // MARK: - Segmented Buffer
    var textSegments: [String] = []
    var audioChunks: [Data?] = []
    var chunkDurations: [TimeInterval] = []
    var totalDuration: TimeInterval = 0

    var currentChunkIndex: Int = 0
    var currentPlayingIndex: Int = 0

    var dataTasks: [URLSessionDataTask] = []
    var inFlightIndexes: Set<Int> = []

    // MARK: - Seek State
    var seekTime: TimeInterval?
    var isSeeking: Bool = false

    // MARK: - Config
    let settingsManager = SettingsManager.shared
    var mediaType: String = "wav"

    // MARK: - Constants
    let endEpsilon: TimeInterval = 0.03

    // MARK: - Lightweight caches (perf)
    let langCache = NSCache<NSString, NSString>()
    let wordCountCache = NSCache<NSString, NSNumber>()

    // Track the current generation so outdated callbacks are ignored.
    var currentGenerationID = UUID()

    // Realtime streaming state flags.
    private(set) var isRealtimeMode: Bool = false
    private var realtimeFinalized: Bool = false

    // Queue indexes to ensure realtime streaming sends one request at a time.
    var pendingRealtimeIndexes: [Int] = []

    // MARK: - Entry (batched playback mode)
    func startProcessing(text: String) {
        currentGenerationID = UUID()
        isRealtimeMode = false
        realtimeFinalized = false
        pendingRealtimeIndexes.removeAll()

        resetPlayer()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.12)) {
            isShowingAudioPlayer = true
        }
        isLoading = true
        isAudioPlaying = true
        currentTime = 0

        let v = settingsManager.voiceSettings
        textSegments = v.enableStreaming ? splitTextIntoMeaningfulSegments(text) : [text]

        let n = textSegments.count
        audioChunks = Array(repeating: nil, count: n)
        chunkDurations = Array(repeating: 0, count: n)
        totalDuration = 0

        currentChunkIndex = 0
        currentPlayingIndex = 0

        sendNextSegment()
    }

    // MARK: - Realtime pipeline
    /// Start a realtime audio stream. Segments are appended progressively.
    func startRealtimeStream() {
        currentGenerationID = UUID()
        isRealtimeMode = true
        realtimeFinalized = false
        pendingRealtimeIndexes.removeAll()

        resetPlayer()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.12)) {
            isShowingAudioPlayer = true
        }
        // Treat the stream as loading until audio actually begins.
        isLoading = true
        isAudioPlaying = false
        currentTime = 0

        textSegments = []
        audioChunks = []
        chunkDurations = []
        totalDuration = 0

        currentChunkIndex = 0
        currentPlayingIndex = 0
    }

    /// Append a playable text segment. Realtime streams enqueue sequentially.
    func appendRealtimeSegment(_ text: String) {
        guard isRealtimeMode else { return }
        let idx = textSegments.count
        textSegments.append(text)
        audioChunks.append(nil)
        chunkDurations.append(0)
        // Ensure realtime segments are processed in order.
        enqueueRealtimeIndex(idx)
    }

    /// Finalise the realtime stream and finish playback when all audio completes.
    func finishRealtimeStream() {
        guard isRealtimeMode else { return }
        realtimeFinalized = true
        // Let the regular playback lifecycle close everything once buffers drain.
    }

    // MARK: - Play/Pause
    func togglePlayback() {
        if !isAudioPlaying && playbackFinished() {
            currentPlayingIndex = 0
            currentTime = 0
        }

        if !isAudioPlaying {
            // User requested playback.
            if playbackFinished() {
                isAudioPlaying = false
                return
            }
            if let chunkOpt = audioChunks[safe: currentPlayingIndex], let _ = chunkOpt {
                let didStart = playAudioChunk(at: currentPlayingIndex, fromTime: currentTime, shouldPlay: true)
                if isRealtimeMode {
                    // Consider playback active only when audio starts.
                    isAudioPlaying = didStart
                    isLoading = !didStart
                } else {
                    isAudioPlaying = didStart
                    if didStart { isLoading = false }
                }
            } else {
                isBuffering = true
                startStallWatchdog()
                if isRealtimeMode {
                    // Realtime mode stays in loading state until audio arrives.
                    isLoading = true
                    isAudioPlaying = false
                } else {
                    // Batched mode keeps the previous behaviour.
                    isAudioPlaying = true
                }
            }
        } else {
            // Pause playback.
            isAudioPlaying = false
            audioPlayer?.pause()
            stopAudioTimer()
            startStallWatchdog()
            isBuffering = false
        }
    }

    // MARK: - Seek
    func forward15Seconds() { seek(to: currentTime + 15, shouldPlay: isAudioPlaying) }
    func backward15Seconds() { seek(to: currentTime - 15, shouldPlay: isAudioPlaying) }

    func seek(to time: TimeInterval, shouldPlay: Bool = false) {
        guard totalDuration > 0 || !chunkDurations.isEmpty else { return }

        let maxKnown = max(totalDuration, startTime(forSegment: chunkDurations.count))
        var newT = time
        if maxKnown > 0 {
            newT = max(0, min(time, maxKnown))
        } else {
            newT = max(0, time)
        }
        currentTime = newT

        if allChunksLoaded() && currentTime >= totalDuration - endEpsilon {
            currentTime = totalDuration
            finishPlayback()
            return
        }

        let target = findSegmentIndex(for: newT)

        if target != currentPlayingIndex {
            audioPlayer?.stop()
            audioPlayer = nil
            currentPlayingIndex = target
        }

        if let chunkOpt = audioChunks[safe: target], let _ = chunkOpt {
            _ = playAudioChunk(at: target, fromTime: newT, shouldPlay: shouldPlay)
        } else {
            isBuffering = shouldPlay
            isSeeking = true
            seekTime = newT
            stopAudioTimer()
            startStallWatchdog()
            // Missing realtime segments keep the player in a loading state.
            if isRealtimeMode {
                isLoading = true
                if shouldPlay { isAudioPlaying = false }
            }
            if !inFlightIndexes.contains(target) {
                sendTTSRequest(for: textSegments[target], index: target)
            }
        }
    }

    // MARK: - Reset / Close
    func closeAudioPlayer() {
        resetPlayer()
        isAudioPlaying = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.12)) {
            isShowingAudioPlayer = false
        }
        isLoading = false
        outputLevel = 0
        isRealtimeMode = false
        realtimeFinalized = false
        pendingRealtimeIndexes.removeAll()
    }

    func resetPlayer() {
        dataTasks.forEach { $0.cancel() }
        dataTasks.removeAll()
        inFlightIndexes.removeAll()
        pendingRealtimeIndexes.removeAll()

        audioPlayer?.stop()
        audioPlayer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil

        stopAudioTimer()
        stopStallWatchdog()

        textSegments.removeAll()
        audioChunks.removeAll()
        chunkDurations.removeAll()
        totalDuration = 0

        currentChunkIndex = 0
        currentPlayingIndex = 0
        currentTime = 0
        isBuffering = false
        isSeeking = false
        seekTime = nil
        errorMessage = nil
        outputLevel = 0

        lastObservedPlaybackTime = 0
        lastProgressTimestamp = Date()
    }

    // MARK: - Realtime queue helpers (NEW)
    func enqueueRealtimeIndex(_ index: Int) {
        if !isRealtimeMode {
            // Send immediately in batched mode.
            sendTTSRequest(for: textSegments[index], index: index)
            return
        }
        if inFlightIndexes.isEmpty {
            sendTTSRequest(for: textSegments[index], index: index)
        } else {
            pendingRealtimeIndexes.append(index)
        }
    }

    func processRealtimeQueueIfNeeded() {
        guard isRealtimeMode else { return }
        guard inFlightIndexes.isEmpty else { return }
        guard !pendingRealtimeIndexes.isEmpty else { return }
        let next = pendingRealtimeIndexes.removeFirst()
        sendTTSRequest(for: textSegments[next], index: next)
    }
}
