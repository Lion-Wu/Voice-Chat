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
    func flushPendingSaves()
}

/// Live session activity bridge used for sidebar ordering during streaming.
@MainActor
protocol ChatSessionActivityPublishing: AnyObject {
    func publishLiveActivity(for session: ChatSession)
}

/// Abstraction over session persistence so view models remain testable and MVVM-friendly.
@MainActor
protocol ChatSessionRepository: ChatSessionPersisting {
    var didPersistSessions: ((Set<UUID>) -> Void)? { get set }
    func attach(context: ModelContext)
    func fetchSessions() -> [ChatSession]
    func createSession(title: String) -> ChatSession?
    func delete(_ session: ChatSession)
    func setImmediatePersistenceEnabled(_ enabled: Bool)
}

/// SwiftData-backed implementation that centralises throttling and error handling.
@MainActor
final class SwiftDataChatSessionRepository: ChatSessionRepository {
    private var context: ModelContext?
    private var lastSaveTime: [UUID: Date] = [:]
    private var pendingSessionIDs: Set<UUID> = []
    private var pendingSaveTasks: [UUID: Task<Void, Never>] = [:]
    private let throttleInterval: TimeInterval
    private var immediatePersistenceEnabled = false
    var didPersistSessions: ((Set<UUID>) -> Void)?

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
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
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

    func setImmediatePersistenceEnabled(_ enabled: Bool) {
        immediatePersistenceEnabled = enabled
        guard enabled else { return }
        flushPendingSaves()
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
        pendingSessionIDs.insert(session.id)

        switch reason {
        case .immediate:
            session.updatedAt = now
            return saveContext(label: "immediate session save", at: now)
        case .throttled:
            // Keep in-memory ordering accurate even while disk writes are throttled.
            session.updatedAt = now
            if immediatePersistenceEnabled {
                return saveContext(label: "background-forced session save", at: now)
            }
            let last = lastSaveTime[session.id] ?? .distantPast
            let elapsed = now.timeIntervalSince(last)
            guard elapsed >= throttleInterval else {
                schedulePendingSave(for: session.id, after: throttleInterval - elapsed)
                return false
            }

            return saveContext(label: "throttled session save", at: now)
        }
    }

    func flushPendingSaves() {
        _ = saveContext(label: "flush pending session saves", notifyObserver: true)
    }

    @discardableResult
    private func saveContext(
        label: String,
        at saveTime: Date = Date(),
        notifyObserver: Bool = false
    ) -> Bool {
        guard let context else { return false }
        let savedSessionIDs = pendingSessionIDs
        guard context.hasChanges else {
            pendingSessionIDs.subtract(savedSessionIDs)
            cancelPendingSaveTasks(for: savedSessionIDs)
            return false
        }

        do {
            try context.save()
            for sessionID in savedSessionIDs {
                lastSaveTime[sessionID] = saveTime
            }
            pendingSessionIDs.subtract(savedSessionIDs)
            cancelPendingSaveTasks(for: savedSessionIDs)
            let shouldNotifyObserver = notifyObserver || savedSessionIDs.count > 1
            if shouldNotifyObserver, !savedSessionIDs.isEmpty {
                didPersistSessions?(savedSessionIDs)
            }
            return true
        } catch {
            print("SwiftData save failed (\(label)): \(error)")
            return false
        }
    }

    private func schedulePendingSave(for sessionID: UUID, after delay: TimeInterval) {
        guard delay.isFinite else { return }
        let clampedDelay = max(0.05, delay)
        cancelPendingSaveTask(for: sessionID)
        pendingSaveTasks[sessionID] = Task { [weak self] in
            let duration = UInt64(clampedDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.pendingSaveTasks[sessionID] = nil
                _ = self.saveContext(label: "scheduled session save", notifyObserver: true)
            }
        }
    }

    private func cancelPendingSaveTask(for sessionID: UUID) {
        pendingSaveTasks[sessionID]?.cancel()
        pendingSaveTasks[sessionID] = nil
    }

    private func cancelPendingSaveTasks(for sessionIDs: Set<UUID>) {
        for sessionID in sessionIDs {
            cancelPendingSaveTask(for: sessionID)
        }
    }
}
