//
//  ChatSessionMutationController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Combine
import Foundation

@MainActor
final class ChatSessionMutationController {
    private var branchState = ChatMessageBranchState()
    private weak var sessionPersistence: (any ChatSessionPersisting & ChatSessionActivityPublishing)?
    private let branchDidChange: PassthroughSubject<Void, Never>

    init(
        sessionPersistence: (any ChatSessionPersisting & ChatSessionActivityPublishing)?,
        branchDidChange: PassthroughSubject<Void, Never>
    ) {
        self.sessionPersistence = sessionPersistence
        self.branchDidChange = branchDidChange
    }

    func persistSession(_ session: ChatSession, reason: SessionPersistReason = .throttled) {
        sessionPersistence?.ensureSessionTracked(session)
        sessionPersistence?.persist(session: session, reason: reason)
    }

    func markMessageActivity(in session: ChatSession, at date: Date) {
        session.registerMessageActivity(at: date)
    }

    func messageLookup(in session: ChatSession) -> [UUID: ChatMessage] {
        branchState.messageLookup(in: session)
    }

    func activeBranchMessages(in session: ChatSession) -> [ChatMessage] {
        let resolution = branchState.activeBranchMessages(
            in: session,
            repairRootSelection: true
        )
        if resolution.didMutate {
            invalidateMessageLookupCache()
            if resolution.didMutateBranch {
                invalidateBranchMessagesCache()
            }
            persistSession(session, reason: .immediate)
        }

        return resolution.messages
    }

    func invalidateBranchMessagesCache() {
        branchState.invalidateBranchMessages()
    }

    func invalidateMessageLookupCache() {
        branchState.invalidateMessageLookup()
    }

    func invalidateAllCaches() {
        branchState.invalidateAll()
    }

    func publishBranchChange() {
        branchDidChange.send(())
    }

    @discardableResult
    func repairMessageTreeIfNeeded(
        in session: ChatSession,
        isSending: Bool,
        finalizeDanglingActiveAssistantMessages: () -> Bool
    ) -> Bool {
        guard !session.messages.isEmpty else { return false }
        guard !isSending else { return false }

        let repair = ChatMessageBranchResolver.repairMessageTree(in: session)
        var didMutate = repair.didMutate
        let didMutateBranch = repair.didMutateBranch

        if finalizeDanglingActiveAssistantMessages() {
            didMutate = true
        }

        guard didMutate else { return false }

        if didMutateBranch {
            invalidateBranchMessagesCache()
            publishBranchChange()
        }
        invalidateMessageLookupCache()
        persistSession(session, reason: .immediate)
        return true
    }

    @discardableResult
    func switchToMessageVersion(
        _ message: ChatMessage,
        in session: ChatSession,
        isSending: Bool
    ) -> Bool {
        guard !isSending else { return false }
        if let parent = message.parentMessage {
            parent.activeChildMessageID = message.id
        } else {
            session.activeRootMessageID = message.id
        }
        invalidateBranchMessagesCache()
        publishBranchChange()
        persistSession(session, reason: .immediate)
        return true
    }
}
