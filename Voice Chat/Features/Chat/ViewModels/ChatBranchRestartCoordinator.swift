//
//  ChatBranchRestartCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatBranchRestartResult {
    let parentMessageID: UUID
    let didMutateBranch: Bool
}

struct ChatBranchRestoreResult {
    let didRestoreBranch: Bool
}

enum ChatBranchRestartIntent: Equatable, Sendable {
    case regenerate(messageID: UUID)
    case retry(errorMessageID: UUID)

    var messageID: UUID {
        switch self {
        case .regenerate(let messageID):
            return messageID
        case .retry(let errorMessageID):
            return errorMessageID
        }
    }
}

struct ChatBranchRestartConfirmation: Equatable, Sendable {
    let intent: ChatBranchRestartIntent
    let userMessageID: UUID
    let canContinueTextOnly: Bool
}

enum ChatBranchRestartRequestResult: Equatable, Sendable {
    case started
    case requiresUnsupportedImageConfirmation(ChatBranchRestartConfirmation)
    case unavailable
}

@MainActor
final class ChatBranchRestartCoordinator {
    private enum PendingRestore {
        case message(parentID: UUID, previousChildID: UUID?)
    }

    private var pendingRestore: PendingRestore?

    func prepareRestart(from parent: ChatMessage) -> ChatBranchRestartResult {
        pendingRestore = .message(parentID: parent.id, previousChildID: parent.activeChildMessageID)
        parent.activeChildMessageID = nil
        return ChatBranchRestartResult(parentMessageID: parent.id, didMutateBranch: true)
    }

    func restorePendingBranchIfAssistantDidNotStart(
        currentAssistantMessageID: UUID?,
        messageLookup: [UUID: ChatMessage]
    ) -> ChatBranchRestoreResult {
        guard currentAssistantMessageID == nil,
              let pendingRestore else {
            return ChatBranchRestoreResult(didRestoreBranch: false)
        }

        self.pendingRestore = nil
        guard case let .message(parentID, previousChildID) = pendingRestore,
              let parent = messageLookup[parentID] else {
            return ChatBranchRestoreResult(didRestoreBranch: false)
        }

        parent.activeChildMessageID = previousChildID
        return ChatBranchRestoreResult(didRestoreBranch: true)
    }

    func clearPendingRestore() {
        pendingRestore = nil
    }
}
