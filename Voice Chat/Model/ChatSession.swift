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

    // MARK: - Relation
    @Relationship(deleteRule: .cascade) var messages: [ChatMessage]

    // MARK: - Init
    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
    }
}
