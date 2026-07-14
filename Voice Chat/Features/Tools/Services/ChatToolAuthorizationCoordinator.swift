//
//  ChatToolAuthorizationCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.24.
//

import Foundation

actor ChatToolAuthorizationCoordinator {
    static let defaultDecisionTimeoutNanoseconds: UInt64 = 120_000_000_000

    private struct PendingDecision {
        let token: UUID
        let continuation: CheckedContinuation<Bool, Never>
        let timeoutTask: Task<Void, Never>
    }

    private var pendingDecisions: [String: PendingDecision] = [:]

    func waitForDecision(
        requestID: String,
        timeoutNanoseconds: UInt64 = defaultDecisionTimeoutNanoseconds
    ) async -> Bool {
        let token = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let existing = pendingDecisions.removeValue(forKey: requestID) {
                    existing.timeoutTask.cancel()
                    existing.continuation.resume(returning: false)
                }
                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    } catch {
                        return
                    }
                    await self?.resolve(requestID: requestID, token: token, allowed: false)
                }
                pendingDecisions[requestID] = PendingDecision(
                    token: token,
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
            }
        } onCancel: {
            Task {
                await self.resolve(requestID: requestID, token: token, allowed: false)
            }
        }
    }

    func resolve(requestID: String, allowed: Bool) {
        guard let pending = pendingDecisions.removeValue(forKey: requestID) else { return }
        pending.timeoutTask.cancel()
        pending.continuation.resume(returning: allowed)
    }

    private func resolve(requestID: String, token: UUID, allowed: Bool) {
        guard let pending = pendingDecisions[requestID], pending.token == token else { return }
        pendingDecisions.removeValue(forKey: requestID)
        pending.timeoutTask.cancel()
        pending.continuation.resume(returning: allowed)
    }

    func cancelAll() {
        let pending = pendingDecisions
        pendingDecisions.removeAll()
        for decision in pending.values {
            decision.timeoutTask.cancel()
            decision.continuation.resume(returning: false)
        }
    }
}
