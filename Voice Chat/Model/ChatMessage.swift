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

    // MARK: - Branching
    var activeChildMessageID: UUID?

    // MARK: - Content
    var content: String
    var isUser: Bool
    var isActive: Bool
    var createdAt: Date

    // MARK: - Telemetry & Metadata
    var modelIdentifier: String?
    var apiBaseURL: String?
    var requestID: UUID?
    var streamStartedAt: Date?
    var streamFirstTokenAt: Date?
    var streamCompletedAt: Date?
    var timeToFirstToken: TimeInterval?
    var streamDuration: TimeInterval?
    var generationDuration: TimeInterval?
    var deltaCount: Int = 0
    var characterCount: Int = 0
    var promptMessageCount: Int?
    var promptCharacterCount: Int?
    var finishReason: String?
    var errorDescription: String?

    // MARK: - Relation
    @Relationship(inverse: \ChatSession.messages) var session: ChatSession?
    @Relationship(inverse: \ChatMessage.childMessages) var parentMessage: ChatMessage?
    @Relationship var childMessages: [ChatMessage]

    // MARK: - Init
    init(
        content: String,
        isUser: Bool,
        isActive: Bool = true,
        createdAt: Date = Date(),
        activeChildMessageID: UUID? = nil,
        modelIdentifier: String? = nil,
        apiBaseURL: String? = nil,
        requestID: UUID? = nil,
        streamStartedAt: Date? = nil,
        streamFirstTokenAt: Date? = nil,
        streamCompletedAt: Date? = nil,
        timeToFirstToken: TimeInterval? = nil,
        streamDuration: TimeInterval? = nil,
        generationDuration: TimeInterval? = nil,
        deltaCount: Int = 0,
        characterCount: Int = 0,
        promptMessageCount: Int? = nil,
        promptCharacterCount: Int? = nil,
        finishReason: String? = nil,
        errorDescription: String? = nil,
        session: ChatSession? = nil,
        parentMessage: ChatMessage? = nil,
        childMessages: [ChatMessage] = []
    ) {
        self.id = UUID()
        self.activeChildMessageID = activeChildMessageID
        self.content = content
        self.isUser = isUser
        self.isActive = isActive
        self.createdAt = createdAt
        self.modelIdentifier = modelIdentifier
        self.apiBaseURL = apiBaseURL
        self.requestID = requestID
        self.streamStartedAt = streamStartedAt
        self.streamFirstTokenAt = streamFirstTokenAt
        self.streamCompletedAt = streamCompletedAt
        self.timeToFirstToken = timeToFirstToken
        self.streamDuration = streamDuration
        self.generationDuration = generationDuration
        self.deltaCount = deltaCount
        self.characterCount = characterCount
        self.promptMessageCount = promptMessageCount
        self.promptCharacterCount = promptCharacterCount
        self.finishReason = finishReason
        self.errorDescription = errorDescription
        self.session = session
        self.parentMessage = parentMessage
        self.childMessages = childMessages
    }
}
