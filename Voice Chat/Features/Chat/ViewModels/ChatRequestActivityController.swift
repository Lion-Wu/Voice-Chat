//
//  ChatRequestActivityController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

@MainActor
final class ChatRequestActivityController {
    struct PublishedState: Equatable {
        var isLoading: Bool
        var isPriming: Bool
    }

    var onPublishedStateChange: ((PublishedState) -> Void)?

    private var state: ChatRequestActivityState

    init(state: ChatRequestActivityState = ChatRequestActivityState()) {
        self.state = state
    }

    var sending: Bool { state.sending }
    var hasActiveTextRequest: Bool { state.hasActiveTextRequest }
    var currentAssistantMessageID: UUID? {
        get { state.currentAssistantMessageID }
        set { state.currentAssistantMessageID = newValue }
    }
    var interruptedAssistantMessageID: UUID? {
        get { state.interruptedAssistantMessageID }
        set { state.interruptedAssistantMessageID = newValue }
    }
    var pendingAssistantParentMessageID: UUID? {
        get { state.pendingAssistantParentMessageID }
        set { state.pendingAssistantParentMessageID = newValue }
    }

    var publishedState: PublishedState {
        PublishedState(
            isLoading: state.isLoading,
            isPriming: state.isPriming
        )
    }

    func publishCurrentState() {
        onPublishedStateChange?(publishedState)
    }

    func markActive(pendingParentMessageID: UUID?) {
        updatePublishedState {
            $0.markActive(pendingParentMessageID: pendingParentMessageID)
        }
    }

    func markInactive() {
        updatePublishedState {
            $0.markInactive()
        }
    }

    func clearAssistantTracking() {
        state.clearAssistantTracking()
    }

    func keepActiveForRetry() {
        updatePublishedState {
            $0.keepActiveForRetry()
        }
    }

    func markAssistantDeltaStarted() {
        updatePublishedState {
            $0.markAssistantDeltaStarted()
        }
    }

    private func updatePublishedState(_ mutate: (inout ChatRequestActivityState) -> Void) {
        let before = publishedState
        mutate(&state)
        let after = publishedState
        if after != before {
            onPublishedStateChange?(after)
        }
    }
}
