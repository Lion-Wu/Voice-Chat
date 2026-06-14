//
//  TTSRequestRetryState.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct TTSAutoRetryPublishedState: Equatable, Sendable {
    let isRetrying: Bool
    let retryAttempt: Int
    let retryLastError: String?
}

struct TTSRequestRetryState: Equatable, Sendable {
    private var retryCounts: [Int: Int] = [:]
    private var retryingIndexes: Set<Int> = []
    private var lastErrorMessage: String?

    var isRetrying: Bool {
        !retryingIndexes.isEmpty
    }

    var publishedState: TTSAutoRetryPublishedState {
        TTSAutoRetryPublishedState(
            isRetrying: isRetrying,
            retryAttempt: retryingIndexes.compactMap { retryCounts[$0] }.max() ?? 0,
            retryLastError: lastErrorMessage
        )
    }

    func nextAttempt(for index: Int) -> Int {
        (retryCounts[index] ?? 0) + 1
    }

    mutating func markScheduled(
        index: Int,
        attempt: Int,
        lastErrorMessage: String
    ) -> TTSAutoRetryPublishedState {
        retryCounts[index] = max(0, attempt)
        retryingIndexes.insert(index)
        let trimmed = lastErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            self.lastErrorMessage = trimmed
        }
        return publishedState
    }

    mutating func clear(index: Int) -> TTSAutoRetryPublishedState {
        retryCounts.removeValue(forKey: index)
        retryingIndexes.remove(index)
        if !isRetrying {
            lastErrorMessage = nil
        }
        return publishedState
    }

    mutating func reset() -> TTSAutoRetryPublishedState {
        retryCounts.removeAll()
        retryingIndexes.removeAll()
        lastErrorMessage = nil
        return publishedState
    }
}
