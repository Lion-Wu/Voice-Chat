//
//  ChatAutoRetryCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

@MainActor
final class ChatAutoRetryCoordinator {
    private var retryTask: Task<Void, Never>?
    private let streamRetryCoordinator: ChatStreamRetryCoordinator

    init(streamRetryCoordinator: ChatStreamRetryCoordinator = ChatStreamRetryCoordinator()) {
        self.streamRetryCoordinator = streamRetryCoordinator
    }

    func shouldAutoRetry(after error: Error, currentAttempt: Int) -> Bool {
        streamRetryCoordinator.shouldAutoRetry(after: error, currentAttempt: currentAttempt)
    }

    func planRetry(
        after error: Error,
        errorText: String,
        currentState: ChatStreamRetryState,
        hasAssistantMessage: Bool
    ) -> ChatStreamRetryPlan {
        streamRetryCoordinator.planRetry(
            after: error,
            errorText: errorText,
            currentState: currentState,
            hasAssistantMessage: hasAssistantMessage
        )
    }

    func scheduleRetry(after delay: TimeInterval, retryAction: @escaping @MainActor () -> Void) {
        cancelScheduledRetry()
        retryTask = Task { @MainActor in
            await NetworkRetry.sleep(seconds: delay)
            guard !Task.isCancelled else { return }
            retryAction()
        }
    }

    func clearRetryStateAfterProgress(_ state: ChatStreamRetryState) -> ChatStreamRetryState {
        streamRetryCoordinator.clearedAfterProgress(from: state)
    }

    func cancelScheduledRetry() {
        retryTask?.cancel()
        retryTask = nil
    }
}
