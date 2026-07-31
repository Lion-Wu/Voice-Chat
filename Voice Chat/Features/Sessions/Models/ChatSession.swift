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
    var lastMessageID: UUID?
    /// Persisted sidebar-only projection. `nil` identifies legacy rows that
    /// still need a one-message backfill; an empty string is a valid summary.
    var sidebarPreviewText: String?
    var activeRootMessageID: UUID?

    // MARK: - Relation
    @Relationship(deleteRule: .cascade) var messages: [ChatMessage]

    // Streaming changes identify their owning message as they happen. Keeping
    // this transient index avoids walking the complete relationship on every
    // throttled save of a long conversation.
    @Transient private var messagesNeedingTransientPersistence: [UUID: ChatMessage] = [:]
    @Transient private var didInitializeTransientPersistenceTracking = false

    // MARK: - Init
    init(title: String = String(localized: "New Chat")) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastMessageAt = nil
        self.lastMessageID = nil
        self.sidebarPreviewText = ""
        self.activeRootMessageID = nil
        self.messages = []
    }
}

extension ChatSession {
    /// Conversation activity time used for list sorting/grouping.
    /// Sidebar ordering should track message activity only.
    /// Metadata writes (e.g. branch selection/repair) must not reorder sessions.
    var lastActivityAt: Date {
        lastMessageAt ?? createdAt
    }

    func registerMessageActivity(_ message: ChatMessage) {
        if let current = lastMessageAt {
            if message.createdAt > current {
                lastMessageAt = message.createdAt
                lastMessageID = message.id
                sidebarPreviewText = Self.sidebarPreviewText(for: message)
            }
        } else {
            lastMessageAt = message.createdAt
            lastMessageID = message.id
            sidebarPreviewText = Self.sidebarPreviewText(for: message)
        }
    }

    func synchronizeTransientMessageStateForPersistence() {
        if !didInitializeTransientPersistenceTracking {
            for message in messages where message.assistantSegmentsNeedPersistence {
                messagesNeedingTransientPersistence[message.id] = message
            }
            didInitializeTransientPersistenceTracking = true
        }

        for message in messagesNeedingTransientPersistence.values {
            message.synchronizeAssistantSegmentsForPersistence()
        }
    }

    func hydrateTransientMessageState() {
        for message in messages {
            message.hydrateAssistantSegmentsIfNeeded()
            if message.assistantSegmentsNeedPersistence {
                messagesNeedingTransientPersistence[message.id] = message
            }
        }
        didInitializeTransientPersistenceTracking = true
    }

    func markTransientMessageStatePersisted() {
        for message in messagesNeedingTransientPersistence.values {
            message.markAssistantSegmentsPersisted()
        }
        messagesNeedingTransientPersistence.removeAll(keepingCapacity: true)
    }

    func markTransientMessageStatePersistenceFailed() {
        for message in messagesNeedingTransientPersistence.values {
            message.markAssistantSegmentsPersistenceFailed()
        }
    }

    /// Marks the first metadata-only fetch as initialized without touching the
    /// messages relationship or discarding registrations from live objects.
    func prepareForMetadataOnlyPersistence() {
        // A repeated fetch in the same ModelContext can return an already-live
        // session while another conversation is awaiting a throttled save.
        // Never clear registrations that were made by those in-memory objects.
        guard !didInitializeTransientPersistenceTracking else { return }
        didInitializeTransientPersistenceTracking = true
    }

    func registerTransientMessagePersistence(_ message: ChatMessage) {
        messagesNeedingTransientPersistence[message.id] = message
    }

    func refreshSidebarPreviewIfLatest(_ message: ChatMessage) {
        guard lastMessageID == message.id else { return }
        sidebarPreviewText = Self.sidebarPreviewText(for: message)
    }

    func applySidebarSummaryBackfill(from latestMessage: ChatMessage?) {
        lastMessageAt = latestMessage?.createdAt
        lastMessageID = latestMessage?.id
        sidebarPreviewText = Self.sidebarPreviewText(for: latestMessage)
    }

    static func sidebarPreviewText(for message: ChatMessage?) -> String {
        guard let message else { return "" }
        let bodyText = message.content
            .extractThinkParts()
            .body
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bodyText.isEmpty else { return "" }

        // Preserve the existing sidebar presentation contract exactly.
        let snippet = bodyText.prefix(60)
        return bodyText.count > 60 ? "\(snippet)…" : String(snippet)
    }
}
