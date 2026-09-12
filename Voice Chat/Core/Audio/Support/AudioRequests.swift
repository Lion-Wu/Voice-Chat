//
//  AudioRequests.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

struct TTSRequestContext: Equatable, Sendable {
    let segmentText: String
    let index: Int
    let generationID: UUID
    let advanceSequenceOnSuccess: Bool
}

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
        let snapshot = currentTTSSettingsSnapshot()
        if snapshot.provider == .personalVoice {
            return NSLocalizedString(
                "Apple Personal Voice is not authorized or available.",
                comment: "Shown when Apple Personal Voice synthesis cannot start"
            )
        }
        return String(
            format: NSLocalizedString("Unable to construct TTS URL from %@", comment: "Shown when the TTS endpoint URL cannot be built"),
            snapshot.serverAddress
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
        guard let configuration = makeTTSConfiguration(isRealtime: isRealtimeMode) else {
            handleTTSFailure(
                .fatal,
                segmentText: segmentText,
                index: index,
                generationID: currentGenerationID,
                advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                lastErrorMessage: invalidTTSConfigurationMessage()
            )
            return
        }
        currentTTSConfiguration = configuration
        inFlightIndexes.insert(index)
        refreshPlaybackLoadState()

        let genAtRequest = currentGenerationID
        if configuration.provider.usesAppleSpeechSynthesizer {
            startAppleSpeechSynthesis(
                for: segmentText,
                index: index,
                generationID: genAtRequest,
                advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                configuration: configuration
            )
            return
        }

        let request: URLRequest
        do {
            request = try TTSRequestBuilder.makeRequest(
                for: segmentText,
                configuration: configuration
            )
        } catch {
            inFlightIndexes.remove(index)
            handleTTSFailure(
                .fatal,
                segmentText: segmentText,
                index: index,
                generationID: genAtRequest,
                advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                lastErrorMessage: error.localizedDescription
            )
            refreshPlaybackLoadState()
            concludeRealtimeIfIdle()
            return
        }

        let requestID = UUID()
        let context = TTSRequestContext(
            segmentText: segmentText,
            index: index,
            generationID: genAtRequest,
            advanceSequenceOnSuccess: advanceSequenceOnSuccess
        )
        let transport = NetworkDataRequest(
            id: requestID,
            request: request,
            session: ttsSession,
            queue: ttsNetworkQueue,
            onLongWait: { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.activeDataRequests[index]?.id == requestID else { return }
                    self.ttsRequestIssue = TTSRequestIssue(
                        kind: .longWait,
                        requestContext: context,
                        message: NSLocalizedString(
                            "Connected, but audio is not ready yet. You can keep waiting or retry.",
                            comment: "Non-fatal wait for a complete generated audio segment"
                        )
                    )
                }
            }
        ) { [weak self] data, resp, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.activeDataRequests[index]?.id == requestID else { return }
                self.activeDataRequests.removeValue(forKey: index)
                guard genAtRequest == self.currentGenerationID else { return }
                if self.ttsRequestIssue?.kind == .longWait,
                   self.ttsRequestIssue?.segmentIndex == index {
                    self.ttsRequestIssue = nil
                }

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

                self.acceptSynthesizedAudio(
                    data,
                    segmentText: segmentText,
                    index: index,
                    generationID: genAtRequest,
                    advanceSequenceOnSuccess: advanceSequenceOnSuccess
                )
            }
        }
        activeDataRequests[index] = transport
        transport.start()
    }

    private func startAppleSpeechSynthesis(
        for segmentText: String,
        index: Int,
        generationID: UUID,
        advanceSequenceOnSuccess: Bool,
        configuration: TTSSynthesisConfiguration
    ) {
        let requestID = UUID()
        let session = AppleSpeechSynthesisSession.start(
            text: segmentText,
            voiceIdentifier: configuration.appleSpeechVoiceIdentifier,
            provider: configuration.provider
        ) { [weak self] result in
            guard let self else { return }
            self.activeAppleSpeechSessions.removeValue(forKey: requestID)
            guard generationID == self.currentGenerationID else { return }

            defer {
                self.inFlightIndexes.remove(index)
                self.refreshPlaybackLoadState()
                if self.isRealtimeMode {
                    self.processRealtimeQueueIfNeeded()
                }
                self.concludeRealtimeIfIdle()
            }

            switch result {
            case .success(let data):
                self.acceptSynthesizedAudio(
                    data,
                    segmentText: segmentText,
                    index: index,
                    generationID: generationID,
                    advanceSequenceOnSuccess: advanceSequenceOnSuccess
                )
            case .failure(.cancelled):
                return
            case .failure(let error):
                self.handleTTSFailure(
                    error.disposition,
                    segmentText: segmentText,
                    index: index,
                    generationID: generationID,
                    advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                    lastErrorMessage: error.localizedDescription
                )
            }
        }
        activeAppleSpeechSessions[requestID] = session
    }

    private func acceptSynthesizedAudio(
        _ data: Data,
        segmentText: String,
        index: Int,
        generationID: UUID,
        advanceSequenceOnSuccess: Bool
    ) {
        do {
            let chunk = try TTSAudioChunkDecoder.decode(data)
            clearTTSAutoRetry(for: index)
            if ttsRequestIssue?.segmentIndex == index {
                ttsRequestIssue = nil
            }
            audioChunks[index] = chunk.data
            audioMotionTimelines[index] = nil
            chunkDurations[index] = chunk.duration
            scheduleAudioMotionTimeline(
                for: chunk.data,
                at: index,
                generationID: generationID
            )
        } catch {
            handleTTSFailure(
                error.disposition,
                segmentText: segmentText,
                index: index,
                generationID: generationID,
                advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                lastErrorMessage: error.message
            )
            return
        }
        recalcTotalDuration()
        refreshPlaybackLoadState()

        if playbackFinished() {
            finishPlayback()
            return
        }

        if index == currentPlayingIndex {
            let shouldAutoplay = isPlaybackRequested
            let resumeTime: TimeInterval? = {
                if let seek = seekTime { return seek }
                return isBuffering ? currentTime : nil
            }()

            let didStart = playAudioChunk(
                at: index,
                fromTime: resumeTime,
                shouldPlay: shouldAutoplay
            )

            if isRealtimeMode {
                isPlaybackRequested = shouldAutoplay
                isAudioPlaying = shouldAutoplay && didStart
                isLoading = shouldAutoplay && !didStart
            } else {
                isLoading = false
            }
            seekTime = nil
        }

        if index == currentPlayingIndex + 1 {
            prepareNextAudioChunk(at: index)
        }

        if !isRealtimeMode,
           advanceSequenceOnSuccess,
           index == currentChunkIndex {
            currentChunkIndex = index + 1
            refreshPlaybackLoadState()
            sendNextSegment()
        }
    }

}
