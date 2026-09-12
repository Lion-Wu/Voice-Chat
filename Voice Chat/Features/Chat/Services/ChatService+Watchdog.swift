//
//  ChatService+Watchdog.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension ChatService {
    func startWatchdog() {
        stopWatchdog()
        guard let requestTask = activeStreamRequest?.task else { return }
        let monitor = NetworkRequestWaitMonitor(
            queue: stateQueue,
            onConnectionTimeout: { [weak self] in
                guard let self, !self.isCancelled,
                      self.activeStreamRequest?.task === requestTask else { return }
                self.failCurrentStream(with: ChatNetworkError.timeout(NSLocalizedString(
                    "Connection timed out", comment: "Shown when connecting to the chat server takes too long"
                )))
            },
            onLongWait: { [weak self] hasResponseProgress in
                guard let self, !self.isCancelled,
                      self.activeStreamRequest?.task === requestTask else { return }
                self.updateLongWaitNotice(hasResponseProgress ? .awaitingNextToken : .awaitingFirstToken)
            }
        )
        waitMonitor = monitor
        monitor.start()
    }

    func stopWatchdog() {
        waitMonitor?.stop()
        waitMonitor = nil
    }

    func beginBackgroundExecutionForCurrentRequest() {
        backgroundExecutionCoordinator?.begin()
    }

    func endBackgroundExecutionForCurrentRequest() {
        backgroundExecutionCoordinator?.end()
    }

    @MainActor
    func handleBackgroundExecutionInterruption(_ message: String) {
        stateQueue.sync { [self] in
            guard cancelCurrentStreamForBackgroundInterruption() else { return }
            deliverError(ChatNetworkError.timeout(message))
        }
    }

    func cancelCurrentStreamForBackgroundInterruption() -> Bool {
        guard activeStreamRequest != nil || activeToolLoopContext != nil else { return false }
        isCancelled = true
        beginNewStreamCallbackEpoch()
        activeStreamRequest?.task.cancel()
        activeStreamRequest = nil
        cancelActiveToolExecution()
        stopWatchdog()
        activeToolLoopContext = nil
        Task { await toolAuthorizationCoordinator.cancelAll() }
        return true
    }

    func markConnectionEstablishedIfNeeded() {
        waitMonitor?.markConnectionEstablished()
    }

    func updateLongWaitNotice(_ notice: ChatStreamLongWaitNotice?) {
        guard activeLongWaitNotice != notice else { return }
        activeLongWaitNotice = notice
        deliverLongWaitNotice(notice)
    }
}
