//
//  ChatSessionRepository.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/15.
//

import Foundation
import SwiftData

/// Reason for persisting a session, used to throttle streaming writes.
enum SessionPersistReason {
    case throttled
    case immediate
}

/// Persistence contract used by chat-focused view models.
@MainActor
protocol ChatSessionPersisting: AnyObject {
    func ensureSessionTracked(_ session: ChatSession)
    @discardableResult
    func persist(session: ChatSession, reason: SessionPersistReason) -> Bool
}

/// Abstraction over session persistence so view models remain testable and MVVM-friendly.
@MainActor
protocol ChatSessionRepository: ChatSessionPersisting {
    func attach(context: ModelContext)
    func fetchSessions() -> [ChatSession]
    func createSession(title: String) -> ChatSession?
    func delete(_ session: ChatSession)
}

/// SwiftData-backed implementation that centralises throttling and error handling.
@MainActor
final class SwiftDataChatSessionRepository: ChatSessionRepository {
    private var context: ModelContext?
    private var lastSaveTime: [UUID: Date] = [:]
    private let throttleInterval: TimeInterval

    init(throttleInterval: TimeInterval = 1.0) {
        self.throttleInterval = throttleInterval
    }

    func attach(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
    }

    func fetchSessions() -> [ChatSession] {
        guard let context = context else { return [] }
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Fetch sessions error: \(error)")
            return []
        }
    }

    func createSession(title: String) -> ChatSession? {
        guard let context = context else { return nil }
        let session = ChatSession(title: title)
        context.insert(session)
        saveContext(label: "create session")
        return session
    }

    func delete(_ session: ChatSession) {
        guard let context = context else { return }
        context.delete(session)
        saveContext(label: "delete session")
    }

    func ensureSessionTracked(_ session: ChatSession) {
        guard let context = context else { return }
        if session.modelContext == nil {
            context.insert(session)
        }
    }

    @discardableResult
    func persist(session: ChatSession, reason: SessionPersistReason) -> Bool {
        guard context != nil else { return false }
        let now = Date()

        switch reason {
        case .immediate:
            session.updatedAt = now
            lastSaveTime[session.id] = now
            saveContext(label: "immediate session save")
            return true
        case .throttled:
            let last = lastSaveTime[session.id] ?? .distantPast
            guard now.timeIntervalSince(last) >= throttleInterval else { return false }

            lastSaveTime[session.id] = now
            session.updatedAt = now
            saveContext(label: "throttled session save")
            return true
        }
    }

    private func saveContext(label: String) {
        guard let context else { return }
        do {
            try context.save()
        } catch {
            print("SwiftData save failed (\(label)): \(error)")
        }
    }
}
