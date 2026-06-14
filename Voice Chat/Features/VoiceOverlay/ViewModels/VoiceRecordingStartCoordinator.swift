//
//  VoiceRecordingStartCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation

enum VoiceRecordingStartCompletion: Equatable {
    case stale
    case finished
    case restartRequested
}

struct VoiceRecordingStartCoordinator {
    private(set) var isStartingRecording = false
    private(set) var pendingRestartAfterStart = false
    private(set) var startAttemptID: UUID?
    private var startRecordingTask: Task<Void, Never>?
    private var startWatchdogTask: Task<Void, Never>?

    mutating func beginStart(makeID: () -> UUID = UUID.init) -> UUID {
        cancelStartTasks()

        let attemptID = makeID()
        startAttemptID = attemptID
        isStartingRecording = true
        pendingRestartAfterStart = false
        return attemptID
    }

    mutating func registerStartRecordingTask(_ task: Task<Void, Never>) {
        startRecordingTask = task
    }

    mutating func registerStartWatchdogTask(_ task: Task<Void, Never>) {
        startWatchdogTask = task
    }

    func isActiveStartAttempt(_ attemptID: UUID) -> Bool {
        startAttemptID == attemptID && isStartingRecording
    }

    mutating func completeStart(attemptID: UUID) -> VoiceRecordingStartCompletion {
        guard startAttemptID == attemptID else { return .stale }

        isStartingRecording = false
        if pendingRestartAfterStart {
            pendingRestartAfterStart = false
            return .restartRequested
        }
        return .finished
    }

    mutating func requestRestartAfterStartIfNeeded() -> Bool {
        guard isStartingRecording else { return false }
        pendingRestartAfterStart = true
        return true
    }

    mutating func failStart(attemptID: UUID) -> Bool {
        guard startAttemptID == attemptID else { return false }
        guard isStartingRecording else { return false }

        isStartingRecording = false
        pendingRestartAfterStart = false
        startAttemptID = nil
        return true
    }

    mutating func cancelStartTasks() {
        startRecordingTask?.cancel()
        startRecordingTask = nil
        startWatchdogTask?.cancel()
        startWatchdogTask = nil
        startAttemptID = nil
        pendingRestartAfterStart = false
        isStartingRecording = false
    }
}
