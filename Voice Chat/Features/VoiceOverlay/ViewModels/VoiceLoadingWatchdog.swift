//
//  VoiceLoadingWatchdog.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation

@MainActor
final class VoiceLoadingWatchdog {
    private let defaultTimeout: TimeInterval
    private let activeAudioRequestTimeout: TimeInterval
    private let pollInterval: Duration
    private let now: () -> Date
    private var task: Task<Void, Never>?
    private var lastProgressAt: Date?

    var isRunning: Bool {
        task != nil
    }

    init(
        defaultTimeout: TimeInterval = 60,
        activeAudioRequestTimeout: TimeInterval = 120,
        pollInterval: Duration = .seconds(2),
        now: @escaping () -> Date = Date.init
    ) {
        self.defaultTimeout = defaultTimeout
        self.activeAudioRequestTimeout = activeAudioRequestTimeout
        self.pollInterval = pollInterval
        self.now = now
    }

    func start(
        isActive: @escaping @MainActor () -> Bool,
        voiceWorkSnapshot: @escaping @MainActor () -> VoiceWorkSnapshot,
        onTimeout: @escaping @MainActor () -> Void
    ) {
        stop()
        lastProgressAt = now()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: self.pollInterval)
                guard !Task.isCancelled else { return }
                guard isActive() else {
                    self.finish()
                    return
                }

                let currentTime = self.now()
                let lastProgress = self.lastProgressAt ?? currentTime
                let timeout = voiceWorkSnapshot().loadingStallTimeout(
                    defaultTimeout: self.defaultTimeout,
                    activeAudioRequestTimeout: self.activeAudioRequestTimeout
                )
                if currentTime.timeIntervalSince(lastProgress) > timeout {
                    self.finish()
                    onTimeout()
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        finish()
    }

    func markProgress() {
        guard isRunning else { return }
        lastProgressAt = now()
    }

    private func finish() {
        task = nil
        lastProgressAt = nil
    }
}
