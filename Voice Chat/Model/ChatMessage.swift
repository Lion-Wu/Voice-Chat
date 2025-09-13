//
//  ChatMessage.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation
import SwiftData

@Model
final class ChatMessage {
    // MARK: - Identity
    var id: UUID

    // MARK: - Content
    var content: String
    var isUser: Bool
    var isActive: Bool
    var createdAt: Date

    // MARK: - Relation
    @Relationship(inverse: \ChatSession.messages) var session: ChatSession?

    // MARK: - Init
    init(content: String, isUser: Bool, isActive: Bool = true, createdAt: Date = Date(), session: ChatSession? = nil) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.isActive = isActive
        self.createdAt = createdAt
        self.session = session
    }
}
