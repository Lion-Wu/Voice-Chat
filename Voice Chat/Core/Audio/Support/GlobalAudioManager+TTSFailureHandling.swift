//
//  GlobalAudioManager+TTSFailureHandling.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

enum TTSFailureDisposition: Equatable {
    case transient
    case content
    case fatal
}

@MainActor
extension GlobalAudioManager {
    func handleTTSFailure(
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
        let retryCount = ttsRetryState.nextAttempt(for: index)
        guard ttsRetryPolicy.shouldContinue(afterAttempt: retryCount) else {
            return false
        }

        applyTTSAutoRetryPublishedState(
            ttsRetryState.markScheduled(
                index: index,
                attempt: retryCount,
                lastErrorMessage: lastErrorMessage
            )
        )

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
                audioMotionTimelines.append(nil)
                chunkDurations.append(0)
            }
        }

        audioChunks[index] = nil
        audioMotionTimelines[index] = nil
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
            clearRealtimeRequestQueue()
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

    func cancelScheduledTTSAutoRetry(for index: Int) {
        if let task = ttsRetryTasks.removeValue(forKey: index) {
            task.cancel()
        }
    }

    func clearTTSAutoRetry(for index: Int) {
        cancelScheduledTTSAutoRetry(for: index)
        applyTTSAutoRetryPublishedState(ttsRetryState.clear(index: index))
    }
}
