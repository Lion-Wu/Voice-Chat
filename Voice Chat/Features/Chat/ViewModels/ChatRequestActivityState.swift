//
//  ChatRequestActivityState.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct ChatRequestActivityState: Equatable {
    var isLoading = false
    var isPriming = false
    var sending = false
    var currentAssistantMessageID: UUID?
    var interruptedAssistantMessageID: UUID?
    var pendingAssistantParentMessageID: UUID?

    var hasActiveTextRequest: Bool {
        sending || isLoading || isPriming
    }

    mutating func markActive(pendingParentMessageID: UUID?) {
        isPriming = true
        isLoading = true
        sending = true
        currentAssistantMessageID = nil
        interruptedAssistantMessageID = nil
        pendingAssistantParentMessageID = pendingParentMessageID
    }

    mutating func markInactive() {
        isPriming = false
        isLoading = false
        sending = false
    }

    mutating func clearAssistantTracking() {
        currentAssistantMessageID = nil
        interruptedAssistantMessageID = nil
        pendingAssistantParentMessageID = nil
    }

    mutating func keepActiveForRetry() {
        isLoading = true
        sending = true
        if currentAssistantMessageID == nil {
            isPriming = true
        }
    }

    mutating func markAssistantDeltaStarted() {
        isPriming = false
        isLoading = true
    }
}
