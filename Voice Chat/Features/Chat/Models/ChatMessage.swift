//
//  ChatMessage.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation
import SwiftData

enum ChatAssistantSegmentKind: String, Codable, Sendable {
    case reasoning
    case text
}

struct ChatAssistantSegment: Codable, Equatable, Sendable {
    var kind: ChatAssistantSegmentKind
    var itemID: String?
    var text: String
}

enum AssistantStreamSegment: Equatable, Sendable {
    case reasoning(id: String?, text: String)
    case text(id: String?, text: String)
    case tool(ChatToolActivityPlacement)
}

@Model
final class ChatMessage {
    // MARK: - Identity
    var id: UUID

    // MARK: - Branching
    var activeChildMessageID: UUID?

    // MARK: - Content
    var content: String
    var requestContentSnapshot: String?
    var assistantSegmentsData: Data?
    var openAIResponsesConversationItemsData: Data?
    @Transient var transientAssistantSegments: [ChatAssistantSegment]?
    @Transient var assistantSegmentsNeedPersistence = false
    @Transient var assistantSegmentsSynchronizedForPersistence = false
    var imageAttachmentsData: Data?
    var isUser: Bool
    var isActive: Bool
    var createdAt: Date

    // MARK: - Telemetry & Metadata
    var modelIdentifier: String?
    var apiBaseURL: String?
    var thinkingOptionRawValue: String?
    var requestID: UUID?
    var providerResponseID: String?
    var providerResponseIDsData: Data?
    var requestContextFingerprint: String?
    var requestUsedPreviousResponseID: Bool?
    var requestPreviousResponseID: String?
    var streamStartedAt: Date?
    var streamFirstTokenAt: Date?
    var streamCompletedAt: Date?
    var timeToFirstToken: TimeInterval?
    var streamDuration: TimeInterval?
    var generationDuration: TimeInterval?
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
    var toolActivityPlacementsData: Data?

    // MARK: - Relation
    @Relationship(inverse: \ChatSession.messages) var session: ChatSession?
    @Relationship(inverse: \ChatMessage.childMessages) var parentMessage: ChatMessage?
    @Relationship var childMessages: [ChatMessage]

    // MARK: - Init
    init(
        content: String,
        requestContentSnapshot: String? = nil,
        assistantSegments: [ChatAssistantSegment] = [],
        openAIResponsesConversationItems: [JSONValue] = [],
        imageAttachments: [ChatImageAttachment] = [],
        isUser: Bool,
        isActive: Bool = true,
        createdAt: Date = Date(),
        activeChildMessageID: UUID? = nil,
        modelIdentifier: String? = nil,
        apiBaseURL: String? = nil,
        thinkingOptionRawValue: String? = nil,
        requestID: UUID? = nil,
        providerResponseID: String? = nil,
        providerResponseIDs: [String] = [],
        requestContextFingerprint: String? = nil,
        requestUsedPreviousResponseID: Bool? = nil,
        requestPreviousResponseID: String? = nil,
        streamStartedAt: Date? = nil,
        streamFirstTokenAt: Date? = nil,
        streamCompletedAt: Date? = nil,
        timeToFirstToken: TimeInterval? = nil,
        streamDuration: TimeInterval? = nil,
        generationDuration: TimeInterval? = nil,
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
        toolActivityPlacements: [ChatToolActivityPlacement] = [],
        session: ChatSession? = nil,
        parentMessage: ChatMessage? = nil,
        childMessages: [ChatMessage] = []
    ) {
        self.id = UUID()
        self.activeChildMessageID = activeChildMessageID
        self.content = content
        self.requestContentSnapshot = requestContentSnapshot
        self.assistantSegmentsData = ChatMessage.encodeAssistantSegments(assistantSegments)
        self.openAIResponsesConversationItemsData = ChatMessage.encodeOpenAIResponsesConversationItems(
            openAIResponsesConversationItems
        )
        self.transientAssistantSegments = assistantSegments
        self.assistantSegmentsNeedPersistence = false
        self.assistantSegmentsSynchronizedForPersistence = false
        self.imageAttachmentsData = ChatImageAttachment.encodeList(imageAttachments)
        self.isUser = isUser
        self.isActive = isActive
        self.createdAt = createdAt
        self.modelIdentifier = modelIdentifier
        self.apiBaseURL = apiBaseURL
        self.thinkingOptionRawValue = thinkingOptionRawValue
        self.requestID = requestID
        self.providerResponseID = providerResponseID
        self.providerResponseIDsData = ChatMessage.encodeProviderResponseIDs(providerResponseIDs)
        self.requestContextFingerprint = requestContextFingerprint
        self.requestUsedPreviousResponseID = requestUsedPreviousResponseID
        self.requestPreviousResponseID = requestPreviousResponseID
        self.streamStartedAt = streamStartedAt
        self.streamFirstTokenAt = streamFirstTokenAt
        self.streamCompletedAt = streamCompletedAt
        self.timeToFirstToken = timeToFirstToken
        self.streamDuration = streamDuration
        self.generationDuration = generationDuration
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
        self.toolActivityPlacementsData = ChatMessage.encodeToolActivityPlacements(toolActivityPlacements)
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

    var toolActivityPlacements: [ChatToolActivityPlacement] {
        get { ChatMessage.decodeToolActivityPlacements(from: toolActivityPlacementsData) }
        set { toolActivityPlacementsData = ChatMessage.encodeToolActivityPlacements(newValue) }
    }

    var providerResponseIDs: [String] {
        get { ChatMessage.decodeProviderResponseIDs(from: providerResponseIDsData) }
        set { providerResponseIDsData = ChatMessage.encodeProviderResponseIDs(newValue) }
    }

    var assistantSegments: [ChatAssistantSegment] {
        get {
            if let transientAssistantSegments {
                return transientAssistantSegments
            }
            return ChatMessage.decodeAssistantSegments(from: assistantSegmentsData)
        }
        set {
            let previous = transientAssistantSegments
                ?? ChatMessage.decodeAssistantSegments(from: assistantSegmentsData)
            transientAssistantSegments = newValue
            if previous != newValue {
                assistantSegmentsNeedPersistence = true
                assistantSegmentsSynchronizedForPersistence = false
            }
        }
    }

    var openAIResponsesConversationItems: [JSONValue] {
        get { ChatMessage.decodeOpenAIResponsesConversationItems(from: openAIResponsesConversationItemsData) }
        set { openAIResponsesConversationItemsData = ChatMessage.encodeOpenAIResponsesConversationItems(newValue) }
    }

    var assistantText: String {
        let segments = assistantSegments
        let text = segments
            .filter { $0.kind == .text }
            .map(\.text)
            .joined()
        if !text.isEmpty || !segments.isEmpty {
            return text
        }
        return content.extractThinkParts().body
    }

    var assistantReasoningText: String? {
        let segments = assistantSegments
        let reasoning = segments
            .filter { $0.kind == .reasoning }
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !reasoning.isEmpty || !segments.isEmpty {
            return reasoning.isEmpty ? nil : reasoning
        }
        return content.extractThinkParts().think
    }

    var hasAssistantSegments: Bool {
        !assistantSegments.isEmpty
    }

    var hasAssistantOutput: Bool {
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if !assistantSegments.isEmpty {
            return true
        }
        if !toolActivityPlacements.isEmpty {
            return true
        }
        return false
    }

    var renderFingerprintSource: String {
        let segments = assistantSegments
        guard !segments.isEmpty else { return content }
        let segmentSource = segments
            .map { "\($0.kind.rawValue):\($0.itemID ?? ""):\($0.text)" }
            .joined(separator: "\u{1F}")
        return content + "\u{1E}" + segmentSource
    }

    func appendAssistantSegment(_ segment: AssistantStreamSegment) {
        switch segment {
        case let .reasoning(id, text):
            appendAssistantSegment(kind: .reasoning, itemID: id, text: text)
        case let .text(id, text):
            appendAssistantSegment(kind: .text, itemID: id, text: text)
        case .tool:
            break
        }
    }

    var thinkingOption: ModelThinkingOption? {
        get {
            thinkingOptionRawValue.flatMap(ModelThinkingOption.normalized)
        }
        set {
            thinkingOptionRawValue = newValue?.rawValue
        }
    }

    private static func encodeToolActivityPlacements(_ placements: [ChatToolActivityPlacement]) -> Data? {
        guard !placements.isEmpty else { return nil }
        return try? JSONEncoder().encode(placements)
    }

    private static func decodeToolActivityPlacements(from data: Data?) -> [ChatToolActivityPlacement] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ChatToolActivityPlacement].self, from: data)) ?? []
    }

    private static func encodeProviderResponseIDs(_ responseIDs: [String]) -> Data? {
        let normalized = responseIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return nil }
        return try? JSONEncoder().encode(normalized)
    }

    private static func decodeProviderResponseIDs(from data: Data?) -> [String] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func appendAssistantSegment(kind: ChatAssistantSegmentKind, itemID: String?, text: String) {
        guard !text.isEmpty else { return }
        var segments = transientAssistantSegments
            ?? ChatMessage.decodeAssistantSegments(from: assistantSegmentsData)
        if let index = segments.indices.last,
           segments[index].kind == kind,
           segments[index].itemID == itemID {
            segments[index].text += text
        } else {
            segments.append(ChatAssistantSegment(kind: kind, itemID: itemID, text: text))
        }
        transientAssistantSegments = segments
        assistantSegmentsNeedPersistence = true
        assistantSegmentsSynchronizedForPersistence = false
    }

    func hydrateAssistantSegmentsIfNeeded() {
        guard transientAssistantSegments == nil else { return }
        transientAssistantSegments = ChatMessage.decodeAssistantSegments(from: assistantSegmentsData)
        assistantSegmentsNeedPersistence = false
        assistantSegmentsSynchronizedForPersistence = false
    }

    @discardableResult
    func synchronizeAssistantSegmentsForPersistence() -> Bool {
        guard assistantSegmentsNeedPersistence,
              !assistantSegmentsSynchronizedForPersistence,
              let transientAssistantSegments else {
            return false
        }
        assistantSegmentsData = ChatMessage.encodeAssistantSegments(transientAssistantSegments)
        assistantSegmentsSynchronizedForPersistence = true
        return true
    }

    func markAssistantSegmentsPersisted() {
        guard assistantSegmentsNeedPersistence,
              assistantSegmentsSynchronizedForPersistence else {
            return
        }
        assistantSegmentsNeedPersistence = false
        assistantSegmentsSynchronizedForPersistence = false
    }

    func markAssistantSegmentsPersistenceFailed() {
        guard assistantSegmentsNeedPersistence else { return }
        assistantSegmentsSynchronizedForPersistence = false
    }

    private static func encodeAssistantSegments(_ segments: [ChatAssistantSegment]) -> Data? {
        guard !segments.isEmpty else { return nil }
        return try? JSONEncoder().encode(segments)
    }

    private static func decodeAssistantSegments(from data: Data?) -> [ChatAssistantSegment] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ChatAssistantSegment].self, from: data)) ?? []
    }

    private static func encodeOpenAIResponsesConversationItems(_ items: [JSONValue]) -> Data? {
        guard !items.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(items)
    }

    private static func decodeOpenAIResponsesConversationItems(from data: Data?) -> [JSONValue] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([JSONValue].self, from: data)) ?? []
    }
}
