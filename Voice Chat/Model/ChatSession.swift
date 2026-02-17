//
//  ChatSession.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation
import SwiftData

@Model
final class ChatSession {
    // MARK: - Identity
    var id: UUID

    // MARK: - Content
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastMessageAt: Date?
    var activeRootMessageID: UUID?

    // MARK: - Relation
    @Relationship(deleteRule: .cascade) var messages: [ChatMessage]

    // MARK: - Init
    init(title: String = String(localized: "New Chat")) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastMessageAt = nil
        self.activeRootMessageID = nil
        self.messages = []
    }
}

extension ChatSession {
    /// Conversation activity time used for list sorting/grouping.
    /// Use the newer timestamp between message activity and metadata updates.
    var lastActivityAt: Date {
        guard let lastMessageAt else { return updatedAt }
        return max(lastMessageAt, updatedAt)
    }

    func registerMessageActivity(at date: Date) {
        if let current = lastMessageAt {
            if date > current {
                lastMessageAt = date
            }
        } else {
            lastMessageAt = date
        }
    }
}
