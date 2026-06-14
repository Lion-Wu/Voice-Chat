//
//  ChatServiceBackgroundExecutionCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class ChatServiceBackgroundExecutionCoordinator: @unchecked Sendable {
    private let onInterruption: @MainActor (String) -> Void

#if canImport(UIKit)
    private let taskName: String
    private var generation: UInt64 = 0
    @MainActor private var generationOnMain: UInt64 = 0
    @MainActor private var taskIdentifier: UIBackgroundTaskIdentifier = .invalid
#endif

    init(
        taskName: String = "VoiceChat.TextStreaming",
        onInterruption: @escaping @MainActor (String) -> Void
    ) {
        self.onInterruption = onInterruption
#if canImport(UIKit)
        self.taskName = taskName
#endif
    }

    func begin() {
#if canImport(UIKit)
        generation &+= 1
        let currentGeneration = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.beginOnMain(for: currentGeneration)
        }
#endif
    }

    func end() {
#if canImport(UIKit)
        generation &+= 1
        let currentGeneration = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.endOnMain(for: currentGeneration)
        }
#endif
    }

    func endSynchronouslyIfNeeded() {
#if canImport(UIKit)
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                endOnMain(for: UInt64.max)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    endOnMain(for: UInt64.max)
                }
            }
        }
#endif
    }

#if canImport(UIKit)
    @MainActor
    private func beginOnMain(for currentGeneration: UInt64) {
        guard currentGeneration >= generationOnMain else { return }
        generationOnMain = currentGeneration
        endOnMainInternal()

        var identifier: UIBackgroundTaskIdentifier = .invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: taskName) { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleExpirationOnMain(taskIdentifier: identifier, generation: currentGeneration)
            }
        }
        taskIdentifier = identifier

        guard identifier != .invalid else {
            guard UIApplication.shared.applicationState == .background else { return }
            handleUnavailableOnMain(for: currentGeneration)
            return
        }
    }

    @MainActor
    private func endOnMain(for currentGeneration: UInt64) {
        guard currentGeneration >= generationOnMain else { return }
        generationOnMain = currentGeneration
        endOnMainInternal()
    }

    @MainActor
    private func endOnMainInternal() {
        guard taskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskIdentifier)
        taskIdentifier = .invalid
    }

    @MainActor
    private func handleUnavailableOnMain(for currentGeneration: UInt64) {
        guard currentGeneration >= generationOnMain else { return }
        onInterruption(NSLocalizedString(
            "Background execution unavailable",
            comment: "Shown when iOS cannot grant background runtime for an active text generation stream"
        ))
    }

    @MainActor
    private func handleExpirationOnMain(
        taskIdentifier expiredIdentifier: UIBackgroundTaskIdentifier,
        generation currentGeneration: UInt64
    ) {
        guard expiredIdentifier != .invalid else { return }
        guard currentGeneration >= generationOnMain else { return }
        guard taskIdentifier == expiredIdentifier else { return }

        generationOnMain = currentGeneration
        UIApplication.shared.endBackgroundTask(expiredIdentifier)
        if taskIdentifier == expiredIdentifier {
            taskIdentifier = .invalid
        }

        onInterruption(NSLocalizedString(
            "Background execution time expired",
            comment: "Shown when iOS ends background time for an active text generation stream"
        ))
    }
#endif
}
