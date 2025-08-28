//
//  ChatMessage.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation

final class ChatMessage: Identifiable, Codable, Equatable, ObservableObject {
    // MARK: - Identity
    var id = UUID()

    // MARK: - Content
    @Published var content: String
    var isUser: Bool
    var isActive: Bool = true

    // MARK: - Init
    init(content: String, isUser: Bool, isActive: Bool = true) {
        self.content = content
        self.isUser = isUser
        self.isActive = isActive
    }

    // MARK: - Equatable
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case id, content, isUser, isActive
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        isUser = try container.decode(Bool.self, forKey: .isUser)
        isActive = try container.decode(Bool.self, forKey: .isActive)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(isUser, forKey: .isUser)
        try container.encode(isActive, forKey: .isActive)
    }
}
