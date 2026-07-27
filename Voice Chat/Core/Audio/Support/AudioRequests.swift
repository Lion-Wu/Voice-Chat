//
//  AudioRequests.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

@MainActor
extension GlobalAudioManager {

    // MARK: - URL Builder
    func constructTTSURL(from rawAddress: String) -> URL? {
        TTSConfigurationResolver(mediaType: mediaType).constructTTSURL(from: rawAddress)
    }

    func constructTTSURL() -> URL? {
        constructTTSURL(from: currentTTSSettingsSnapshot().serverAddress)
    }

    func makeTTSConfiguration(isRealtime: Bool) -> TTSSynthesisConfiguration? {
        TTSConfigurationResolver(mediaType: mediaType).makeConfiguration(
            snapshot: currentTTSSettingsSnapshot(),
            isRealtime: isRealtime
        )
    }

    func invalidTTSConfigurationMessage() -> String {
        let address = currentTTSSettingsSnapshot().serverAddress
        return String(
            format: NSLocalizedString("Unable to construct TTS URL from %@", comment: "Shown when the TTS endpoint URL cannot be built"),
            address
        )
    }

    // MARK: - Request Queue (used only in full-text mode)
    func sendNextSegment() {
        guard currentChunkIndex < textSegments.count else { return }
        guard !isRealtimeMode else { return } // Realtime mode does not recurse through the queue.
        let idx = currentChunkIndex
        sendTTSRequest(for: textSegments[idx], index: idx, advanceSequenceOnSuccess: true)
    }

    func sendTTSRequest(
        for segmentText: String,
        index: Int,
        advanceSequenceOnSuccess: Bool = false,
        prioritizeIfDeferred: Bool = false
    ) {
        guard !inFlightIndexes.contains(index) else { return }
        guard !skippedAudioChunkIndexes.contains(index) else {
            if !isRealtimeMode,
               advanceSequenceOnSuccess,
               index == currentChunkIndex {
                currentChunkIndex = index + 1
                refreshPlaybackLoadState()
                sendNextSegment()
            } else {
                refreshPlaybackLoadState()
                if isRealtimeMode { processRealtimeQueueIfNeeded() }
            }
            return
        }
        if index < audioChunks.count, audioChunks[index] != nil {
            clearTTSAutoRetry(for: index)
            if !isRealtimeMode,
               advanceSequenceOnSuccess,
               index == currentChunkIndex {
                currentChunkIndex = index + 1
                refreshPlaybackLoadState()
                sendNextSegment()
            } else {
                refreshPlaybackLoadState()
                if isRealtimeMode { processRealtimeQueueIfNeeded() }
            }
            return
        }
        if isRealtimeMode, hasActiveRealtimeSynthesisWork() {
            if ttsRetryTasks[index] == nil {
                queueRealtimeIndex(index, atFront: prioritizeIfDeferred)
            } else {
                refreshPlaybackLoadState()
            }
            return
        }
        cancelScheduledTTSAutoRetry(for: index)
        guard let configuration = currentTTSConfiguration else {
            self.surfaceTTSIssue(invalidTTSConfigurationMessage())
            return
        }
        inFlightIndexes.insert(index)
        refreshPlaybackLoadState()

        let request: URLRequest
        do {
            request = try TTSRequestBuilder.makeRequest(
                for: segmentText,
                configuration: configuration
            )
        } catch {
            self.surfaceTTSIssue(error.localizedDescription)
            inFlightIndexes.remove(index)
            refreshPlaybackLoadState()
            // In realtime mode continue with the queue to avoid stalling.
            if isRealtimeMode { processRealtimeQueueIfNeeded() }
            return
        }

        let genAtRequest = self.currentGenerationID

        let requestID = UUID()
        let task = ttsSession.dataTask(with: request) { [weak self] (data: Data?, resp: URLResponse?, error: Error?) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.activeDataTasks.removeValue(forKey: requestID)
                guard genAtRequest == self.currentGenerationID else { return }

                defer {
                    self.inFlightIndexes.remove(index)
                    self.refreshPlaybackLoadState()
                    if self.isRealtimeMode {
                        self.processRealtimeQueueIfNeeded()
                    }
                    self.concludeRealtimeIfIdle()
                }

                if let err = error as NSError? {
                    if err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled {
                        return
                    }
                    let message = self.formatTTSNetworkError(err, serverAddress: configuration.serverAddress)
                    self.handleTTSFailure(
                        .transient,
                        segmentText: segmentText,
                        index: index,
                        generationID: genAtRequest,
                        advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                        lastErrorMessage: message
                    )
                    return
                }

                if let failure = TTSHTTPResponseValidator.failure(for: resp, data: data) {
                    self.handleTTSFailure(
                        failure.disposition,
                        segmentText: segmentText,
                        index: index,
                        generationID: genAtRequest,
                        advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                        lastErrorMessage: failure.message
                    )
                    return
                }

                guard let data, !data.isEmpty else {
                    let failure = TTSAudioChunkDecodeFailure.emptyData
                    self.handleTTSFailure(
                        failure.disposition,
                        segmentText: segmentText,
                        index: index,
                        generationID: genAtRequest,
                        advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                        lastErrorMessage: failure.message
                    )
                    return
                }

                // Ensure the arrays grow safely when realtime mode extends them dynamically.
                if index >= self.audioChunks.count {
                    let delta = index - self.audioChunks.count + 1
                    for _ in 0..<delta {
                        self.audioChunks.append(nil)
                        self.audioMotionTimelines.append(nil)
                        self.chunkDurations.append(0)
                    }
                }

                if index < self.audioChunks.count {
                    do {
                        let chunk = try TTSAudioChunkDecoder.decode(data)
                        self.clearTTSAutoRetry(for: index)
                        self.skippedAudioChunkIndexes.remove(index)
                        self.audioChunks[index] = chunk.data
                        self.audioMotionTimelines[index] = nil
                        self.chunkDurations[index] = chunk.duration
                        self.scheduleAudioMotionTimeline(
                            for: chunk.data,
                            at: index,
                            generationID: genAtRequest
                        )
                    } catch let failure as TTSAudioChunkDecodeFailure {
                        self.handleTTSFailure(
                            failure.disposition,
                            segmentText: segmentText,
                            index: index,
                            generationID: genAtRequest,
                            advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                            lastErrorMessage: failure.message
                        )
                        return
                    } catch {
                        let failure = TTSAudioChunkDecodeFailure.unsupportedAudioData
                        self.handleTTSFailure(
                            failure.disposition,
                            segmentText: segmentText,
                            index: index,
                            generationID: genAtRequest,
                            advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                            lastErrorMessage: failure.message
                        )
                        return
                    }
                    self.recalcTotalDuration()
                    self.refreshPlaybackLoadState()
                }

                if self.playbackFinished() {
                    self.finishPlayback()
                    return
                }

                if index == self.currentPlayingIndex {
                    let shouldAutoplay = self.isPlaybackRequested
                    let resumeTime: TimeInterval? = {
                        if let seek = self.seekTime { return seek }
                        return self.isBuffering ? self.currentTime : nil
                    }()

                    let didStart = self.playAudioChunk(
                        at: index,
                        fromTime: resumeTime,
                        shouldPlay: shouldAutoplay
                    )

                    if self.isRealtimeMode {
                        self.isPlaybackRequested = shouldAutoplay
                        self.isAudioPlaying = shouldAutoplay && didStart
                        self.isLoading = shouldAutoplay && !didStart
                    } else {
                        self.isLoading = false
                    }
                    self.seekTime = nil
                }

                if index == self.currentPlayingIndex + 1 {
                    self.prepareNextAudioChunk(at: index)
                }

                if !self.isRealtimeMode,
                   advanceSequenceOnSuccess,
                   index == self.currentChunkIndex {
                    self.currentChunkIndex = index + 1
                    self.refreshPlaybackLoadState()
                    self.sendNextSegment()
                }
            }
        }
        activeDataTasks[requestID] = task
        task.resume()
    }

}
