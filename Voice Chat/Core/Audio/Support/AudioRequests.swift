//
//  AudioRequests.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import AVFoundation
import SwiftUI

private enum TTSFailureDisposition: Equatable {
    case transient
    case content
    case fatal
}

@MainActor
extension GlobalAudioManager {

    // MARK: - URL Builder
    func constructTTSURL(from rawAddress: String) -> URL? {
        let raw = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let normalized: String
        if raw.contains("://") {
            normalized = raw
        } else {
            normalized = "http://\(raw)"
        }

        guard var comps = URLComponents(string: normalized) else { return nil }
        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }
        comps.path = path + "/tts"
        return comps.url
    }

    func constructTTSURL() -> URL? {
        constructTTSURL(from: settingsManager.serverSettings.serverAddress)
    }

    func makeTTSConfiguration(isRealtime: Bool) -> TTSSynthesisConfiguration? {
        let serverAddress = settingsManager.serverSettings.serverAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = constructTTSURL(from: serverAddress) else { return nil }

        let streamingEnabled = settingsManager.voiceSettings.enableStreaming
        let splitMethod: String
        if isRealtime {
            splitMethod = "cut0"
        } else {
            splitMethod = streamingEnabled ? "cut0" : settingsManager.modelSettings.autoSplit
        }

        return TTSSynthesisConfiguration(
            serverAddress: serverAddress,
            url: url,
            textLanguage: settingsManager.serverSettings.textLang,
            referenceAudioPath: settingsManager.selectedPreset?.refAudioPath ?? "",
            promptText: settingsManager.selectedPreset?.promptText ?? "",
            promptLanguage: settingsManager.selectedPreset?.promptLang ?? "auto",
            textSplitMethod: splitMethod,
            mediaType: mediaType,
            usesStreamingSegments: streamingEnabled
        )
    }

    func invalidTTSConfigurationMessage() -> String {
        let address = settingsManager.serverSettings.serverAddress
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

        let params: [String: Any] = [
            "text": segmentText,
            "text_lang": configuration.textLanguage,
            "ref_audio_path": configuration.referenceAudioPath,
            "prompt_text": configuration.promptText,
            "prompt_lang": configuration.promptLanguage,
            "batch_size": 1,
            "media_type": configuration.mediaType,
            "text_split_method": configuration.textSplitMethod
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: params) else {
            self.surfaceTTSIssue(NSLocalizedString("Unable to serialize JSON", comment: "Shown when encoding the TTS request body fails"))
            inFlightIndexes.remove(index)
            refreshPlaybackLoadState()
            // In realtime mode continue with the queue to avoid stalling.
            if isRealtimeMode { processRealtimeQueueIfNeeded() }
            return
        }

        var req = URLRequest(url: configuration.url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let genAtRequest = self.currentGenerationID

        var task: URLSessionDataTask?
        task = ttsSession.dataTask(with: req) { [weak self, weak task] (data: Data?, resp: URLResponse?, error: Error?) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let task {
                    self.dataTasks.removeAll(where: { $0 === task })
                }
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

                if let http = resp as? HTTPURLResponse {
                    if !(200...299).contains(http.statusCode) {
                        let preview = data.flatMap { String(data: $0, encoding: .utf8) }?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let message: String
                        if preview.isEmpty {
                            message = String(format: NSLocalizedString("TTS server error: %d", comment: "Shown when the TTS server returns a non-success status"), http.statusCode)
                        } else {
                            let snippet = preview.prefix(180)
                            message = String(format: NSLocalizedString("TTS server error: %d (%@)", comment: "Shown when the TTS server returns a non-success status plus body"), http.statusCode, String(snippet))
                        }
                        self.handleTTSFailure(
                            self.failureDisposition(forHTTPStatusCode: http.statusCode),
                            segmentText: segmentText,
                            index: index,
                            generationID: genAtRequest,
                            advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                            lastErrorMessage: message
                        )
                        return
                    }

                    if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
                       !type.contains("audio") && !type.contains("octet-stream") {
                        let preview = data.flatMap { String(data: $0, encoding: .utf8) }?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let message: String
                        if preview.isEmpty {
                            message = NSLocalizedString("TTS response was not audio data.", comment: "Shown when TTS returns a non-audio MIME type")
                        } else {
                            let snippet = preview.prefix(180)
                            message = String(format: NSLocalizedString("TTS response was not audio: %@", comment: "Shown when TTS returns non-audio body"), String(snippet))
                        }
                        self.handleTTSFailure(
                            .content,
                            segmentText: segmentText,
                            index: index,
                            generationID: genAtRequest,
                            advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                            lastErrorMessage: message
                        )
                        return
                    }
                }

                guard let data = data, !data.isEmpty else {
                    let message = NSLocalizedString("No data received", comment: "Shown when the TTS server returns an empty body")
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

                // Ensure the arrays grow safely when realtime mode extends them dynamically.
                if index >= self.audioChunks.count {
                    let delta = index - self.audioChunks.count + 1
                    for _ in 0..<delta {
                        self.audioChunks.append(nil)
                        self.chunkDurations.append(0)
                    }
                }

                if index < self.audioChunks.count {
                    do {
                        let p = try AVAudioPlayer(data: data)
                        self.clearTTSAutoRetry(for: index)
                        self.skippedAudioChunkIndexes.remove(index)
                        self.audioChunks[index] = data
                        self.chunkDurations[index] = max(0, p.duration)
                    } catch {
                        self.handleTTSFailure(
                            .content,
                            segmentText: segmentText,
                            index: index,
                            generationID: genAtRequest,
                            advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                            lastErrorMessage: NSLocalizedString("Received audio data could not be played.", comment: "Shown when AVAudioPlayer fails to read TTS audio data")
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
        if let task {
            task.resume()
            dataTasks.append(task)
        }
    }

    private func failureDisposition(forHTTPStatusCode statusCode: Int) -> TTSFailureDisposition {
        if NetworkRetryability.shouldRetry(statusCode: statusCode) {
            return .transient
        }
        switch statusCode {
        case 400, 413, 422:
            return .content
        default:
            return .fatal
        }
    }

    private func handleTTSFailure(
        _ disposition: TTSFailureDisposition,
        segmentText: String,
        index: Int,
        generationID: UUID,
        advanceSequenceOnSuccess: Bool,
        lastErrorMessage: String
    ) {
        switch disposition {
        case .fatal:
            clearTTSAutoRetry(for: index)
            surfaceTTSIssue(lastErrorMessage)
            stopPlaybackAfterTerminalTTSFailure()
        case .transient, .content:
            if scheduleTTSAutoRetry(
                segmentText: segmentText,
                index: index,
                generationID: generationID,
                advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                lastErrorMessage: lastErrorMessage
            ) {
                return
            }

            clearTTSAutoRetry(for: index)
            if disposition == .content {
                markTTSChunkSkipped(
                    index: index,
                    advanceSequenceOnSuccess: advanceSequenceOnSuccess
                )
            } else {
                surfaceTTSIssue(lastErrorMessage)
                stopPlaybackAfterTerminalTTSFailure()
            }
        }
    }

    @discardableResult
    private func scheduleTTSAutoRetry(
        segmentText: String,
        index: Int,
        generationID: UUID,
        advanceSequenceOnSuccess: Bool,
        lastErrorMessage: String
    ) -> Bool {
        let retryCount = (ttsRetryCounts[index] ?? 0) + 1
        guard ttsRetryPolicy.shouldContinue(afterAttempt: retryCount) else {
            return false
        }

        ttsRetryCounts[index] = retryCount
        ttsRetryingIndexes.insert(index)
        updateTTSAutoRetryPublishedState(lastErrorMessage: lastErrorMessage)

        let delay = ttsRetryPolicy.delay(forRetryCount: retryCount)

        cancelScheduledTTSAutoRetry(for: index)
        ttsRetryTasks[index] = Task { [weak self] in
            await NetworkRetry.sleep(seconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.currentGenerationID == generationID else { return }
                if self.skippedAudioChunkIndexes.contains(index)
                    || (index < self.audioChunks.count && self.audioChunks[index] != nil) {
                    self.clearTTSAutoRetry(for: index)
                    return
                }
                self.ttsRetryTasks[index] = nil
                self.sendTTSRequest(
                    for: segmentText,
                    index: index,
                    advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                    prioritizeIfDeferred: true
                )
            }
        }
        return true
    }

    private func markTTSChunkSkipped(
        index: Int,
        advanceSequenceOnSuccess: Bool
    ) {
        guard index >= 0 else { return }

        if index >= audioChunks.count {
            let delta = index - audioChunks.count + 1
            for _ in 0..<delta {
                audioChunks.append(nil)
                chunkDurations.append(0)
            }
        }

        audioChunks[index] = nil
        chunkDurations[index] = 0
        skippedAudioChunkIndexes.insert(index)
        recalcTotalDuration()
        refreshPlaybackLoadState()

        surfaceTTSNotice(skippedTTSChunkNotice(for: index))

        if !isRealtimeMode,
           advanceSequenceOnSuccess,
           index == currentChunkIndex {
            currentChunkIndex = index + 1
            refreshPlaybackLoadState()
            sendNextSegment()
        }

        if index == currentPlayingIndex {
            _ = playAudioChunk(
                at: index,
                shouldPlay: isPlaybackRequested || isAudioPlaying || isBuffering || isLoading
            )
        }

        concludeFullTextPlaybackIfResolved()
    }

    private func concludeFullTextPlaybackIfResolved() {
        guard !isRealtimeMode else { return }
        guard currentChunkIndex >= textSegments.count else { return }
        guard allChunksLoaded() else { return }

        if totalDuration <= endEpsilon {
            stopAudioTimer()
            stopStallWatchdog()
            isLoading = false
            isPlaybackRequested = false
            isAudioPlaying = false
            isBuffering = false
            isSeeking = false
            seekTime = nil
            refreshPlaybackLoadState()
        } else if playbackFinished() {
            finishPlayback()
        }
    }

    private func stopPlaybackAfterTerminalTTSFailure() {
        if isRealtimeMode {
            pendingRealtimeIndexes.removeAll()
        }
        isPlaybackRequested = false
        if isBuffering {
            isBuffering = false
            stopStallWatchdog()
        }
        if !isAudioPlaying {
            isLoading = false
            stopAudioTimer()
            stopStallWatchdog()
        }
        refreshPlaybackLoadState()
    }

    private func skippedTTSChunkNotice(for index: Int) -> String {
        let rawText = textSegments[safe: index] ?? ""
        let normalized = rawText
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let previewSource = normalized.isEmpty ? rawText.trimmingCharacters(in: .whitespacesAndNewlines) : normalized
        let preview: String
        if previewSource.count > 120 {
            preview = "\(previewSource.prefix(120))..."
        } else {
            preview = previewSource
        }

        return String(
            format: NSLocalizedString("The following text failed to generate and was ignored: %@", comment: "Shown when a TTS chunk failed repeatedly and was ignored with the source text"),
            preview.isEmpty ? "-" : preview
        )
    }

    private func cancelScheduledTTSAutoRetry(for index: Int) {
        if let task = ttsRetryTasks.removeValue(forKey: index) {
            task.cancel()
        }
    }

    private func clearTTSAutoRetry(for index: Int) {
        cancelScheduledTTSAutoRetry(for: index)
        ttsRetryCounts.removeValue(forKey: index)
        ttsRetryingIndexes.remove(index)
        updateTTSAutoRetryPublishedState(lastErrorMessage: nil)
    }

    private func updateTTSAutoRetryPublishedState(lastErrorMessage: String?) {
        isRetrying = !ttsRetryingIndexes.isEmpty
        retryAttempt = ttsRetryingIndexes.compactMap { ttsRetryCounts[$0] }.max() ?? 0
        if let lastErrorMessage {
            let trimmed = lastErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            retryLastError = trimmed.isEmpty ? nil : trimmed
        } else if !isRetrying {
            retryLastError = nil
        }
    }
}
