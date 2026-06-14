//
//  ChatStreamRetryStatusController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

@MainActor
final class ChatStreamRetryStatusController {
    struct PublishedState: Equatable {
        var isRetrying: Bool
        var retryAttempt: Int
        var retryLastError: String?
    }

    var onPublishedStateChange: ((PublishedState) -> Void)?

    private let autoRetryCoordinator: ChatAutoRetryCoordinator
    private var state: ChatStreamRetryState

    init(
        autoRetryCoordinator: ChatAutoRetryCoordinator = ChatAutoRetryCoordinator(),
        state: ChatStreamRetryState = ChatStreamRetryState()
    ) {
        self.autoRetryCoordinator = autoRetryCoordinator
        self.state = state
    }

    var publishedState: PublishedState {
        PublishedState(
            isRetrying: state.isRetrying,
            retryAttempt: state.retryAttempt,
            retryLastError: state.retryLastError
        )
    }

    func publishCurrentState() {
        onPublishedStateChange?(publishedState)
    }

    func shouldAutoRetry(after error: Error) -> Bool {
        autoRetryCoordinator.shouldAutoRetry(
            after: error,
            currentAttempt: state.retryAttempt
        )
    }

    func planRetry(
        after error: Error,
        errorText: String,
        hasAssistantMessage: Bool
    ) -> ChatStreamRetryPlan {
        let plan = autoRetryCoordinator.planRetry(
            after: error,
            errorText: errorText,
            currentState: state,
            hasAssistantMessage: hasAssistantMessage
        )
        applyState(plan.state)
        return plan
    }

    func scheduleRetry(after delay: TimeInterval, retryAction: @escaping @MainActor () -> Void) {
        autoRetryCoordinator.scheduleRetry(after: delay, retryAction: retryAction)
    }

    func cancelScheduledRetry() {
        autoRetryCoordinator.cancelScheduledRetry()
    }

    func clearStateAfterProgressIfNeeded() {
        applyState(autoRetryCoordinator.clearRetryStateAfterProgress(state))
    }

    func reset() {
        cancelScheduledRetry()
        applyState(ChatStreamRetryState())
    }

    private func applyState(_ newState: ChatStreamRetryState) {
        let before = publishedState
        state = newState
        let after = publishedState
        if after != before {
            onPublishedStateChange?(after)
        }
    }
}
