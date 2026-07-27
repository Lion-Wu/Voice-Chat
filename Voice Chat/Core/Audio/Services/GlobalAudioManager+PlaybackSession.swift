//
//  GlobalAudioManager+PlaybackSession.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

@MainActor
extension GlobalAudioManager {
    // MARK: - Entry (Full-text mode)

    func startProcessing(text: String) {
        currentGenerationID = UUID()
        let generationID = currentGenerationID
        let configuration = makeTTSConfiguration(isRealtime: false)
        isRealtimeMode = false
        realtimeFinalized = false
        realtimeRequestQueue.removeAll()

        resetPlayer()
        currentTTSConfiguration = configuration
        isShowingAudioPlayer = true
        isLoading = true
        isPlaybackRequested = true
        isAudioPlaying = false
        currentTime = 0

        textSegments = []
        audioChunks = []
        audioMotionTimelines = []
        chunkDurations = []
        totalDuration = 0
        currentChunkIndex = 0
        currentPlayingIndex = 0
        refreshPlaybackLoadState()

        guard let configuration else {
            isLoading = false
            isPlaybackRequested = false
            isAudioPlaying = false
            refreshPlaybackLoadState()
            surfaceTTSIssue(invalidTTSConfigurationMessage())
            return
        }

        let streamingEnabled = configuration.usesStreamingSegments
        let worker = segmentationWorker

        Task.detached(priority: .userInitiated) { [weak self] in
            let segments: [String]
            if streamingEnabled {
                segments = await worker.splitTextIntoMeaningfulSegments(text)
            } else {
                segments = [text]
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.currentGenerationID == generationID else { return }
                self.prepareSegmentsForPlayback(segments)
            }
        }
    }

    // MARK: - Realtime Pipeline

    /// Starts a realtime voice stream. Segments are appended later via `appendRealtimeSegment`.
    func startRealtimeStream() {
        currentGenerationID = UUID()
        let configuration = makeTTSConfiguration(isRealtime: true)
        isRealtimeMode = true
        realtimeFinalized = false
        realtimeRequestQueue.removeAll()

        resetPlayer()
        currentTTSConfiguration = configuration
        isShowingAudioPlayer = true
        isLoading = true
        isPlaybackRequested = true
        isAudioPlaying = false
        currentTime = 0

        textSegments = []
        audioChunks = []
        audioMotionTimelines = []
        chunkDurations = []
        totalDuration = 0

        currentChunkIndex = 0
        currentPlayingIndex = 0
        refreshPlaybackLoadState()

        guard configuration != nil else {
            isLoading = false
            isPlaybackRequested = false
            isAudioPlaying = false
            refreshPlaybackLoadState()
            surfaceTTSIssue(invalidTTSConfigurationMessage())
            return
        }
    }

    /// Appends a segment to be converted to speech. Realtime mode enqueues the work, while
    /// regular mode sends it immediately.
    func appendRealtimeSegment(_ text: String) {
        guard isRealtimeMode else { return }
        guard currentTTSConfiguration != nil else {
            surfaceTTSIssue(invalidTTSConfigurationMessage())
            return
        }
        let idx = textSegments.count
        textSegments.append(text)
        audioChunks.append(nil)
        audioMotionTimelines.append(nil)
        chunkDurations.append(0)
        refreshPlaybackLoadState()
        enqueueRealtimeIndex(idx)
    }

    /// Marks the realtime stream as complete. Playback ends naturally once all buffers finish.
    func finishRealtimeStream() {
        guard isRealtimeMode else { return }
        realtimeFinalized = true
        refreshPlaybackLoadState()
        concludeRealtimeIfIdle()
    }

    // MARK: - Play/Pause

    func togglePlayback() {
        let playbackRequestedOrActive = isPlaybackRequested || isAudioPlaying

        if !playbackRequestedOrActive && playbackFinished() {
            currentPlayingIndex = 0
            currentTime = 0
        }

        if !playbackRequestedOrActive {
            isPlaybackRequested = true
            if playbackFinished() {
                isPlaybackRequested = false
                isAudioPlaying = false
                return
            }
            if currentPlayingIndex < audioChunks.count {
                let didStart = playAudioChunk(at: currentPlayingIndex, fromTime: currentTime, shouldPlay: true)
                if isRealtimeMode {
                    isAudioPlaying = didStart
                    isLoading = !didStart
                } else {
                    isAudioPlaying = didStart
                    if didStart { isLoading = false }
                }
            } else {
                isBuffering = true
                startStallWatchdog()
                isAudioPlaying = false
                if isRealtimeMode { isLoading = true }
            }
        } else {
            isPlaybackRequested = false
            isAudioPlaying = false
            audioPlayer?.pause()
            stopAudioTimer()
            startStallWatchdog()
            isBuffering = false
            isLoading = false
        }
    }

    // MARK: - Seek

    func forward15Seconds() {
        seek(to: currentTime + 15, shouldPlay: isPlaybackRequested || isAudioPlaying)
    }

    func backward15Seconds() {
        seek(to: currentTime - 15, shouldPlay: isPlaybackRequested || isAudioPlaying)
    }

    func seek(to time: TimeInterval, shouldPlay: Bool = false) {
        let maxKnown = max(totalDuration, startTime(forSegment: chunkDurations.count))
        guard maxKnown > 0.0005 else { return }

        var newT = time
        if maxKnown > 0 {
            newT = max(0, min(time, maxKnown))
        } else {
            newT = max(0, time)
        }
        currentTime = newT

        if playbackFinished() {
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

        if skippedAudioChunkIndexes.contains(target) {
            _ = playAudioChunk(at: target, fromTime: newT, shouldPlay: shouldPlay)
        } else if let chunkOpt = audioChunks[safe: target], let _ = chunkOpt {
            _ = playAudioChunk(at: target, fromTime: newT, shouldPlay: shouldPlay)
        } else {
            isBuffering = shouldPlay
            isSeeking = true
            seekTime = newT
            stopAudioTimer()
            startStallWatchdog()
            isPlaybackRequested = shouldPlay
            if shouldPlay { isAudioPlaying = false }
            if isRealtimeMode { isLoading = shouldPlay }
            if target < textSegments.count {
                if isRealtimeMode {
                    enqueueRealtimeIndex(target)
                } else if !inFlightIndexes.contains(target),
                          ttsRetryTasks[target] == nil {
                    sendTTSRequest(for: textSegments[target], index: target)
                }
            }
        }
    }

    // MARK: - Reset / Close

    func closeAudioPlayer() {
        resetPlayer()
        isPlaybackRequested = false
        isAudioPlaying = false
        isShowingAudioPlayer = false
        isLoading = false
        outputAudioLevels = .silent
        outputLevel = 0
        isRealtimeMode = false
        realtimeFinalized = false
        realtimeRequestQueue.removeAll()
    }

    func resetPlayer() {
        activeDataTasks.values.forEach { $0.cancel() }
        activeDataTasks.removeAll()
        inFlightIndexes.removeAll()
        realtimeRequestQueue.removeAll()
        ttsRetryTasks.values.forEach { $0.cancel() }
        ttsRetryTasks.removeAll()
        applyTTSAutoRetryPublishedState(ttsRetryState.reset())
        skippedAudioChunkIndexes.removeAll()
        playbackNoticeDismissTask?.cancel()
        playbackNoticeDismissTask = nil
        playbackNoticeMessage = nil
        currentTTSConfiguration = nil

        audioPlayer?.stop()
        audioPlayer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil

        stopAudioTimer()
        stopStallWatchdog()

        textSegments.removeAll()
        audioChunks.removeAll()
        audioMotionTimelines.removeAll()
        chunkDurations.removeAll()
        skippedAudioChunkIndexes.removeAll()
        totalDuration = 0

        currentChunkIndex = 0
        currentPlayingIndex = 0
        currentTime = 0
        isPlaybackRequested = false
        isAudioPlaying = false
        isBuffering = false
        isSeeking = false
        seekTime = nil
        isPlaybackFullyLoaded = true
        errorMessage = nil
        applyTTSAutoRetryPublishedState(ttsRetryState.reset())
        outputAudioLevels = .silent
        outputLevel = 0

        lastObservedPlaybackTime = 0
        lastProgressTimestamp = Date()
    }

    private func prepareSegmentsForPlayback(_ segments: [String]) {
        textSegments = segments
        let count = segments.count
        audioChunks = Array(repeating: nil, count: count)
        audioMotionTimelines = Array(repeating: nil, count: count)
        chunkDurations = Array(repeating: 0, count: count)
        skippedAudioChunkIndexes.removeAll()
        totalDuration = 0
        currentChunkIndex = 0
        currentPlayingIndex = 0
        refreshPlaybackLoadState()

        guard !segments.isEmpty else {
            isLoading = false
            isPlaybackRequested = false
            isAudioPlaying = false
            isPlaybackFullyLoaded = true
            return
        }
        sendNextSegment()
    }
}
