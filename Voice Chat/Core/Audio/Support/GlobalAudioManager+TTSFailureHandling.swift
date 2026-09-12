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
        if disposition != .fatal,
           scheduleTTSAutoRetry(
                segmentText: segmentText,
                index: index,
                generationID: generationID,
                advanceSequenceOnSuccess: advanceSequenceOnSuccess,
                lastErrorMessage: lastErrorMessage
           ) {
            return
        }

        clearTTSAutoRetry(for: index)
        let requestContext = TTSRequestContext(
            segmentText: segmentText,
            index: index,
            generationID: generationID,
            advanceSequenceOnSuccess: advanceSequenceOnSuccess
        )
        ttsRequestIssue = TTSRequestIssue(
            kind: .failed,
            requestContext: requestContext,
            message: lastErrorMessage
        )
        _ = parkPlaybackAtTerminalTTSFailureIfNeeded()
        refreshPlaybackLoadState()
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
                if index < self.audioChunks.count, self.audioChunks[index] != nil {
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

    @discardableResult
    func parkPlaybackAtTerminalTTSFailureIfNeeded() -> Bool {
        guard ttsRequestIssue?.kind == .failed,
              !audioPlaybackSnapshot.hasPlayableAudioRemaining else {
            return false
        }

        isAudioPlaying = false
        isBuffering = false
        if isRealtimeMode {
            isLoading = false
        }
        stopAudioTimer()
        stopStallWatchdog()
        refreshPlaybackLoadState()
        return true
    }

    @discardableResult
    func retryCurrentTTSRequestIssue() -> Bool {
        guard let issue = ttsRequestIssue,
              issue.requestContext.generationID == currentGenerationID else {
            return false
        }
        let context = issue.requestContext
        if issue.kind == .longWait {
            guard let request = activeDataRequests.removeValue(forKey: context.index) else { return false }
            request.cancel()
            inFlightIndexes.remove(context.index)
        }
        guard !inFlightIndexes.contains(context.index),
              ttsRetryTasks[context.index] == nil else {
            return false
        }

        clearTTSAutoRetry(for: context.index)
        ttsRequestIssue = nil
        sendTTSRequest(
            for: context.segmentText,
            index: context.index,
            advanceSequenceOnSuccess: context.advanceSequenceOnSuccess,
            prioritizeIfDeferred: true
        )
        refreshPlaybackLoadState()
        return inFlightIndexes.contains(context.index) || ttsRetryTasks[context.index] != nil
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
