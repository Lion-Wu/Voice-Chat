//
//  TTSPresetApplyCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct TTSPresetApplyStatus: Equatable {
    var isApplying: Bool = false
    var isRetrying: Bool = false
    var retryAttempt: Int = 0
    var retryLastError: String?
    var lastError: String?
    var lastAppliedAt: Date?
    var lastSucceeded: Bool = false

    static let idle = TTSPresetApplyStatus()

    func starting() -> TTSPresetApplyStatus {
        TTSPresetApplyStatus(
            isApplying: true,
            isRetrying: false,
            retryAttempt: 0,
            retryLastError: nil,
            lastError: nil,
            lastAppliedAt: nil,
            lastSucceeded: false
        )
    }

    func updatingRetry(_ retryStatus: TTSPresetApplyRetryStatus?) -> TTSPresetApplyStatus {
        var next = self
        if let retryStatus {
            next.isRetrying = true
            next.retryAttempt = retryStatus.retryAttempt
            next.retryLastError = retryStatus.lastErrorDescription
        } else {
            next.isRetrying = false
            next.retryAttempt = 0
            next.retryLastError = nil
        }
        return next
    }

    func recordingFailure(_ message: String, at date: Date) -> TTSPresetApplyStatus {
        var next = updatingRetry(nil)
        next.isApplying = false
        next.lastError = message
        next.lastAppliedAt = date
        next.lastSucceeded = false
        return next
    }

    func recordingSuccess(at date: Date) -> TTSPresetApplyStatus {
        var next = updatingRetry(nil)
        next.isApplying = false
        next.lastError = nil
        next.lastAppliedAt = date
        next.lastSucceeded = true
        return next
    }
}

@MainActor
final class TTSPresetApplyCoordinator {
    typealias StatusPublisher = @MainActor @Sendable (TTSPresetApplyStatus) -> Void

    private let presetApplyService: TTSPresetApplyService
    private let now: @Sendable () -> Date
    private(set) var status: TTSPresetApplyStatus

    init(
        presetApplyService: TTSPresetApplyService = TTSPresetApplyService(),
        initialStatus: TTSPresetApplyStatus = .idle,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.presetApplyService = presetApplyService
        self.status = initialStatus
        self.now = now
    }

    func apply(
        _ request: TTSPresetApplyRequest,
        publish: @escaping StatusPublisher
    ) async {
        guard !status.isApplying else { return }
        update(status.starting(), publish: publish)

        do {
            try await presetApplyService.apply(request) { [weak self] retryStatus in
                await MainActor.run {
                    guard let self else { return }
                    self.update(self.status.updatingRetry(retryStatus), publish: publish)
                }
            }
        } catch let applyError as TTSPresetApplyError {
            update(status.recordingFailure(applyError.settingsMessage, at: now()), publish: publish)
            return
        } catch {
            update(status.recordingFailure(error.localizedDescription, at: now()), publish: publish)
            return
        }

        update(status.recordingSuccess(at: now()), publish: publish)
    }

    private func update(_ nextStatus: TTSPresetApplyStatus, publish: StatusPublisher) {
        status = nextStatus
        publish(nextStatus)
    }
}
