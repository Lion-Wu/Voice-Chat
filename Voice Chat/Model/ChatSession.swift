//
//  ChatSession.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation

final class ChatSession: Identifiable, Codable, ObservableObject, Equatable, Hashable {
    // MARK: - Identity
    let id: UUID

    // MARK: - Content
    @Published var messages: [ChatMessage]
    @Published var title: String

    // MARK: - Init
    init() {
        self.id = UUID()
        self.messages = []
        self.title = "New Chat"
    }

    // MARK: - Equatable
    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case id, messages, title
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        title = try container.decode(String.self, forKey: .title)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(messages, forKey: .messages)
        try container.encode(title, forKey: .title)
    }
}
