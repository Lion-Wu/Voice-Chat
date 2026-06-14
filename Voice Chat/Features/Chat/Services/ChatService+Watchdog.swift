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
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard !self.isCancelled else { return }
            let now = Date()

            if let start = self.streamStartAt, self.lastDeltaAt == nil {
                if now.timeIntervalSince(start) > self.firstTokenTimeout {
                    self.dataTask?.cancel()
                    self.dataTask = nil
                    self.stopConnectionWatchdog()
                    self.stopWatchdog()
                    self.endBackgroundExecutionForCurrentRequest()
                    Task { @MainActor in
                        self.onError?(ChatNetworkError.timeout(NSLocalizedString("Connection timed out", comment: "Shown when the chat server request exceeds the timeout")))
                    }
                }
                return
            }

            if let last = self.lastDeltaAt {
                if now.timeIntervalSince(last) > self.silentGapTimeout {
                    self.dataTask?.cancel()
                    self.dataTask = nil
                    self.stopConnectionWatchdog()
                    self.stopWatchdog()
                    self.endBackgroundExecutionForCurrentRequest()
                    Task { @MainActor in
                        self.onError?(ChatNetworkError.timeout(NSLocalizedString("Connection timed out", comment: "Shown when the chat server request exceeds the timeout")))
                    }
                }
            }
        }
        watchdog = timer
        timer.resume()
    }

    func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    func startConnectionWatchdog() {
        stopConnectionWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + connectTimeout, repeating: .never, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard !self.isCancelled else { return }
            guard let task = self.dataTask else { return }
            guard !self.didEstablishConnection else {
                self.stopConnectionWatchdog()
                return
            }
            if task.countOfBytesSent > 0 {
                self.markConnectionEstablishedIfNeeded()
                return
            }
            task.cancel()
            self.dataTask = nil
            self.stopWatchdog()
            self.stopConnectionWatchdog()
            self.endBackgroundExecutionForCurrentRequest()
            Task { @MainActor in
                self.onError?(ChatNetworkError.timeout(NSLocalizedString("Connection timed out", comment: "Shown when connecting to the chat server takes too long")))
            }
        }
        connectionWatchdog = timer
        timer.resume()
    }

    func stopConnectionWatchdog() {
        connectionWatchdog?.cancel()
        connectionWatchdog = nil
    }

    func beginBackgroundExecutionForCurrentRequest() {
        backgroundExecutionCoordinator?.begin()
    }

    func endBackgroundExecutionForCurrentRequest() {
        backgroundExecutionCoordinator?.end()
    }

    @MainActor
    func handleBackgroundExecutionInterruption(_ message: String) {
        let shouldReportError = stateQueue.sync { [self] in
            cancelCurrentStreamForBackgroundInterruption()
        }
        guard shouldReportError else { return }
        onError?(ChatNetworkError.timeout(message))
    }

    func cancelCurrentStreamForBackgroundInterruption() -> Bool {
        guard dataTask != nil else { return false }
        isCancelled = true
        dataTask?.cancel()
        dataTask = nil
        stopConnectionWatchdog()
        stopWatchdog()
        clearActiveEndpointCandidate()
        return true
    }

    func markConnectionEstablishedIfNeeded() {
        guard !didEstablishConnection else { return }
        didEstablishConnection = true
        stopConnectionWatchdog()
    }
}
