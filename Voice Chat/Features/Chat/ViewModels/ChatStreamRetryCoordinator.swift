//
//  ChatStreamRetryCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.13.
//

import Foundation

struct ChatStreamRetryState: Equatable, Sendable {
    var isRetrying: Bool
    var retryAttempt: Int
    var retryLastError: String?

    init(
        isRetrying: Bool = false,
        retryAttempt: Int = 0,
        retryLastError: String? = nil
    ) {
        self.isRetrying = isRetrying
        self.retryAttempt = retryAttempt
        self.retryLastError = retryLastError
    }
}

struct ChatStreamRetryPlan: Equatable, Sendable {
    let state: ChatStreamRetryState
    let delay: TimeInterval
    let shouldPrime: Bool
}

struct ChatStreamRetryCoordinator: Sendable {
    let retryPolicy: NetworkRetryPolicy

    init(
        retryPolicy: NetworkRetryPolicy = NetworkRetryPolicy(
            maxAttempts: 2,
            baseDelay: 0.8,
            maxDelay: 18.0,
            backoffFactor: 1.6,
            jitterRatio: 0.2
        )
    ) {
        self.retryPolicy = retryPolicy
    }

    func shouldAutoRetry(after error: Error, currentAttempt: Int) -> Bool {
        guard retryPolicy.shouldContinue(afterAttempt: currentAttempt + 1) else { return false }
        if NetworkRetryability.isCancellation(error) { return false }
        if let err = error as? ChatNetworkError {
            switch err {
            case .invalidURL:
                return false
            case .timeout:
                return true
            case .emptyResponse:
                return false
            case .serverError(let statusCode, _):
                if let statusCode {
                    return NetworkRetryability.shouldRetry(HTTPStatusError(statusCode: statusCode, bodyPreview: nil))
                }
                return false
            }
        }
        return NetworkRetryability.shouldRetry(error)
    }

    func planRetry(
        after error: Error,
        errorText: String,
        currentState: ChatStreamRetryState,
        hasAssistantMessage: Bool
    ) -> ChatStreamRetryPlan {
        let currentAttempt = currentState.isRetrying ? max(0, currentState.retryAttempt) : 0
        let retryAttempt = currentAttempt + 1
        let state = ChatStreamRetryState(
            isRetrying: true,
            retryAttempt: retryAttempt,
            retryLastError: errorText.isEmpty ? error.localizedDescription : errorText
        )
        return ChatStreamRetryPlan(
            state: state,
            delay: retryPolicy.delay(forRetryCount: retryAttempt),
            shouldPrime: !hasAssistantMessage
        )
    }

    func clearedAfterProgress(from state: ChatStreamRetryState) -> ChatStreamRetryState {
        guard state.isRetrying else { return state }
        return ChatStreamRetryState()
    }
}
