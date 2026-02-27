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
    var imageAttachmentsData: Data?
    var isUser: Bool
    var isActive: Bool
    var createdAt: Date

    // MARK: - Telemetry & Metadata
    var modelIdentifier: String?
    var apiBaseURL: String?
    var requestID: UUID?
    var providerResponseID: String?
    var streamStartedAt: Date?
    var streamFirstTokenAt: Date?
    var streamCompletedAt: Date?
    var timeToFirstToken: TimeInterval?
    var streamDuration: TimeInterval?
    var generationDuration: TimeInterval?
    var inputTokenCount: Int?
    var outputTokenCount: Int?
    var reasoningOutputTokenCount: Int?
    var tokensPerSecond: Double?
    var deltaCount: Int = 0
    var tokenCountSource: String?
    var timeToFirstTokenSource: String?
    var tokensPerSecondSource: String?
    var finishReasonSource: String?
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
        imageAttachments: [ChatImageAttachment] = [],
        isUser: Bool,
        isActive: Bool = true,
        createdAt: Date = Date(),
        activeChildMessageID: UUID? = nil,
        modelIdentifier: String? = nil,
        apiBaseURL: String? = nil,
        requestID: UUID? = nil,
        providerResponseID: String? = nil,
        streamStartedAt: Date? = nil,
        streamFirstTokenAt: Date? = nil,
        streamCompletedAt: Date? = nil,
        timeToFirstToken: TimeInterval? = nil,
        streamDuration: TimeInterval? = nil,
        generationDuration: TimeInterval? = nil,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil,
        reasoningOutputTokenCount: Int? = nil,
        tokensPerSecond: Double? = nil,
        deltaCount: Int = 0,
        tokenCountSource: String? = nil,
        timeToFirstTokenSource: String? = nil,
        tokensPerSecondSource: String? = nil,
        finishReasonSource: String? = nil,
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
        self.imageAttachmentsData = ChatImageAttachment.encodeList(imageAttachments)
        self.isUser = isUser
        self.isActive = isActive
        self.createdAt = createdAt
        self.modelIdentifier = modelIdentifier
        self.apiBaseURL = apiBaseURL
        self.requestID = requestID
        self.providerResponseID = providerResponseID
        self.streamStartedAt = streamStartedAt
        self.streamFirstTokenAt = streamFirstTokenAt
        self.streamCompletedAt = streamCompletedAt
        self.timeToFirstToken = timeToFirstToken
        self.streamDuration = streamDuration
        self.generationDuration = generationDuration
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.reasoningOutputTokenCount = reasoningOutputTokenCount
        self.tokensPerSecond = tokensPerSecond
        self.deltaCount = deltaCount
        self.tokenCountSource = tokenCountSource
        self.timeToFirstTokenSource = timeToFirstTokenSource
        self.tokensPerSecondSource = tokensPerSecondSource
        self.finishReasonSource = finishReasonSource
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

extension ChatMessage {
    // Stored as `deltaCount` for backward store compatibility; semantically this is token count.
    var tokenCount: Int {
        get { deltaCount }
        set { deltaCount = newValue }
    }

    var imageAttachments: [ChatImageAttachment] {
        get { ChatImageAttachment.decodeList(from: imageAttachmentsData) }
        set { imageAttachmentsData = ChatImageAttachment.encodeList(newValue) }
    }

    var hasImageAttachments: Bool {
        !(imageAttachmentsData?.isEmpty ?? true) && !imageAttachments.isEmpty
    }

    var imageAttachmentsFingerprint: Int {
        imageAttachmentsData?.hashValue ?? 0
    }
}
