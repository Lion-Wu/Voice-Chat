//
//  ChatSessionsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation
import SwiftData

@MainActor
final class ChatSessionsViewModel: ObservableObject {
    // MARK: - Published State
    @Published private(set) var chatSessions: [ChatSession] = []
    @Published var selectedSessionID: UUID? = nil

    // MARK: - SwiftData
    private var context: ModelContext?

    // MARK: - Save throttle to prevent excessive writes
    private var lastSaveTime: [UUID: Date] = [:]
    private let throttleInterval: TimeInterval = 1.0

    // MARK: - Derived
    var selectedSession: ChatSession? {
        get {
            guard let id = selectedSessionID else { return nil }
            return chatSessions.first(where: { $0.id == id })
        }
        set { selectedSessionID = newValue?.id }
    }

    var canStartNewSession: Bool {
        if let s = selectedSession {
            return !s.messages.isEmpty
        }
        return true
    }

    // MARK: - Attach Context
    func attach(context: ModelContext) {
        // Avoid attaching the same context multiple times
        if self.context == nil {
            self.context = context
            loadChatSessions()
        }
    }

    // MARK: - Session Ops
    func startNewSession() {
        guard let context else { return }
        let new = ChatSession(title: L10n.Chat.defaultSessionTitle)
        context.insert(new)
        do { try context.save() } catch { print("Save new session error: \(error)") }
        refreshSessionsAndSelect(new.id)
    }

    func addSession(_ session: ChatSession) {
        guard let context else { return }
        // Insert the session if it is not already associated with a context
        if session.modelContext == nil {
            context.insert(session)
        }
        persist(session: session, reason: .immediate)
        refreshSessionsAndSelect(session.id)
    }

    func deleteSession(at offsets: IndexSet) {
        guard let context else { return }
        for index in offsets {
            let s = chatSessions[index]
            context.delete(s) // Cascade deletes associated messages
        }
        do { try context.save() } catch { print("Delete error: \(error)") }
        loadChatSessions()
        if !chatSessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = chatSessions.first?.id
        }
        if chatSessions.isEmpty {
            startNewSession()
        }
    }

    // MARK: - Persistence (SwiftData)
    enum PersistReason { case throttled, immediate }

    func persist(session: ChatSession, reason: PersistReason = .throttled) {
        guard let context else { return }
        session.updatedAt = Date()

        switch reason {
        case .immediate:
            do { try context.save() } catch { print("Immediate save error: \(error)") }
        case .throttled:
            let now = Date()
            let last = lastSaveTime[session.id] ?? .distantPast
            if now.timeIntervalSince(last) >= throttleInterval {
                lastSaveTime[session.id] = now
                do { try context.save() } catch { print("Throttled save error: \(error)") }
            }
        }
    }

    // MARK: - Fetch
    func loadChatSessions() {
        guard let context else { return }
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: nil,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            let fetched = try context.fetch(descriptor)
            chatSessions = fetched
            if selectedSessionID == nil {
                selectedSessionID = chatSessions.first?.id
            }
            if chatSessions.isEmpty {
                startNewSession()
            }
        } catch {
            print("Fetch sessions error: \(error)")
            chatSessions = []
        }
    }

    private func refreshSessionsAndSelect(_ id: UUID?) {
        loadChatSessions()
        if let id { selectedSessionID = id }
    }
}
