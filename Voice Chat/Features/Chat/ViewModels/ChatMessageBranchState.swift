//
//  ChatMessageBranchState.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatMessageBranchState {
    private var branchMessagesCache: [ChatMessage] = []
    private var branchMessagesCacheCount: Int = -1
    private var messageLookupCache: [UUID: ChatMessage] = [:]
    private var messageLookupCacheCount: Int = -1

    mutating func messageLookup(in session: ChatSession) -> [UUID: ChatMessage] {
        let count = session.messages.count
        if count == messageLookupCacheCount && !messageLookupCache.isEmpty {
            return messageLookupCache
        }

        let lookup = ChatMessageBranchResolver.messageLookup(in: session)
        messageLookupCache = lookup
        messageLookupCacheCount = count
        return lookup
    }

    mutating func activeBranchMessages(
        in session: ChatSession,
        repairRootSelection: Bool
    ) -> ChatMessageBranchResolution {
        let count = session.messages.count
        if count == branchMessagesCacheCount && !branchMessagesCache.isEmpty {
            return ChatMessageBranchResolution(
                messages: branchMessagesCache,
                didMutate: false,
                didMutateBranch: false
            )
        }

        let resolution = ChatMessageBranchResolver.activeBranchMessages(
            in: session,
            repairRootSelection: repairRootSelection
        )
        branchMessagesCache = resolution.messages
        branchMessagesCacheCount = count
        return resolution
    }

    mutating func invalidateBranchMessages() {
        branchMessagesCache = []
        branchMessagesCacheCount = -1
    }

    mutating func invalidateMessageLookup() {
        messageLookupCache = [:]
        messageLookupCacheCount = -1
    }

    mutating func invalidateAll() {
        invalidateBranchMessages()
        invalidateMessageLookup()
    }
}
