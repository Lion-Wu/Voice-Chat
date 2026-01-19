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
    @Published private(set) var draftSession: ChatSession = ChatSession()
    @Published var selectedSessionID: UUID? = nil
    @Published private(set) var isRealtimeVoiceLocked: Bool = false

    // MARK: - Cached View Models
    private var viewModelCache: [UUID: ChatViewModel] = [:]

    // MARK: - Dependencies
    private let settingsManager: SettingsManager
    private let reachability: ServerReachabilityMonitor
    private let audioManager: GlobalAudioManager
    private let chatServiceFactory: (ChatServiceConfiguring) -> ChatStreamingService
    private let repository: ChatSessionRepository
    private var cachedChatConfiguration: ChatServiceConfiguration
    private var configurationUpdateTask: Task<Void, Never>?

    // MARK: - Init
    init(
        settingsManager: SettingsManager? = nil,
        reachability: ServerReachabilityMonitor? = nil,
        audioManager: GlobalAudioManager? = nil,
        chatServiceFactory: @escaping (ChatServiceConfiguring) -> ChatStreamingService = { ChatService(configurationProvider: $0) },
        repository: ChatSessionRepository? = nil
    ) {
        self.settingsManager = settingsManager ?? SettingsManager.shared
        self.reachability = reachability ?? ServerReachabilityMonitor.shared
        self.audioManager = audioManager ?? GlobalAudioManager.shared
        self.chatServiceFactory = chatServiceFactory
        self.repository = repository ?? SwiftDataChatSessionRepository()
        self.cachedChatConfiguration = ChatServiceConfiguration(
            apiBaseURL: self.settingsManager.chatSettings.apiURL,
            modelIdentifier: self.settingsManager.chatSettings.selectedModel,
            apiKey: self.settingsManager.chatSettings.apiKey
        )
        self.selectedSessionID = draftSession.id
    }

    private func currentChatConfiguration() -> ChatServiceConfiguration {
        ChatServiceConfiguration(
            apiBaseURL: settingsManager.chatSettings.apiURL,
            modelIdentifier: settingsManager.chatSettings.selectedModel,
            apiKey: settingsManager.chatSettings.apiKey
        )
    }

    // MARK: - Derived
    var selectedSession: ChatSession? {
        get {
            guard let id = selectedSessionID else { return nil }
            if let session = chatSessions.first(where: { $0.id == id }) {
                return session
            }
            if id == draftSession.id {
                return draftSession
            }
            return nil
        }
        set { selectedSessionID = newValue?.id }
    }

    var canStartNewSession: Bool {
        !isRealtimeVoiceLocked
    }

    // MARK: - Chat service configuration
    func refreshChatConfigurationIfNeeded() {
        ensureChatConfigurationCurrent()
    }

    private func ensureChatConfigurationCurrent() {
        let latest = currentChatConfiguration()
        guard latest != cachedChatConfiguration else { return }
        cachedChatConfiguration = latest
        configurationUpdateTask?.cancel()
        configurationUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Defer to the next run loop tick to avoid publishing during a view update cycle.
            self.viewModelCache.values.forEach { $0.updateChatConfiguration(latest) }
        }
    }

    // MARK: - View Model Access
    func viewModel(for session: ChatSession) -> ChatViewModel {
        ensureChatConfigurationCurrent()
        if let cached = viewModelCache[session.id] {
            cached.attach(session: session)
            return cached
        }
        let config = cachedChatConfiguration
        let vm = ChatViewModel(
            chatSession: session,
            chatService: chatServiceFactory(config),
            chatServiceFactory: chatServiceFactory,
            settingsManager: settingsManager,
            reachability: reachability,
            audioManager: audioManager,
            sessionPersistence: self
        )
        viewModelCache[session.id] = vm
        return vm
    }

    // MARK: - Attach Context
    func attach(context: ModelContext) {
        repository.attach(context: context)
        loadChatSessions()
    }

    // MARK: - Session Ops
    func startNewSession() {
        guard !isRealtimeVoiceLocked else { return }
        selectedSessionID = draftSession.id
    }

    private func cacheViewModel(for session: ChatSession) {
        ensureChatConfigurationCurrent()
        if let existing = viewModelCache[session.id] {
            existing.attach(session: session)
            viewModelCache[session.id] = existing
            return
        }

        let config = cachedChatConfiguration
        viewModelCache[session.id] = ChatViewModel(
            chatSession: session,
            chatService: chatServiceFactory(config),
            chatServiceFactory: chatServiceFactory,
            settingsManager: settingsManager,
            reachability: reachability,
            audioManager: audioManager,
            sessionPersistence: self
        )
    }

    func addSession(_ session: ChatSession) {
        ensureChatConfigurationCurrent()
        repository.ensureSessionTracked(session)
        cacheViewModel(for: session)
        persist(session: session, reason: .immediate)
        selectedSessionID = session.id
    }

    func deleteSession(at offsets: IndexSet) {
        for index in offsets {
            let s = chatSessions[index]
            viewModelCache.removeValue(forKey: s.id)
            repository.delete(s) // SwiftData cascades to remove related messages.
        }
        loadChatSessions() // Keeps list in sync with persisted state.
    }

    // MARK: - Persistence (SwiftData)
    @discardableResult
    func persist(session: ChatSession, reason: SessionPersistReason = .throttled) -> Bool {
        guard shouldPersist(session) else { return false }
        let didPersist = repository.persist(session: session, reason: reason)
        if didPersist {
            Task { @MainActor [weak self] in
                // Run after the current call stack to keep SwiftUI happy.
                self?.updateInMemoryOrdering(with: session)
                self?.promoteDraftIfNeeded(session)
            }
        }
        return didPersist
    }

    // MARK: - Fetch
    func loadChatSessions() {
        let fetched = repository.fetchSessions()
        chatSessions = orderedSessions(fetched)
        pruneStaleViewModels(keeping: fetched)
        ensureChatConfigurationCurrent()
        ensureValidSelection()
    }

    private func pruneStaleViewModels(keeping sessions: [ChatSession]) {
        let validIDs = Set(sessions.map(\.id)).union([draftSession.id])
        let staleKeys = viewModelCache.keys.filter { !validIDs.contains($0) }
        for key in staleKeys {
            viewModelCache.removeValue(forKey: key)
        }
    }

    private func updateInMemoryOrdering(with session: ChatSession) {
        var updated = chatSessions
        if let idx = updated.firstIndex(where: { $0.id == session.id }) {
            updated[idx] = session
        } else {
            updated.append(session)
        }

        chatSessions = orderedSessions(updated)
        ensureValidSelection()
    }

    func updateRealtimeVoiceLock(_ active: Bool) {
        if isRealtimeVoiceLocked != active {
            isRealtimeVoiceLocked = active
        }
    }

    private func orderedSessions(_ sessions: [ChatSession]) -> [ChatSession] {
        sessions.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func shouldPersist(_ session: ChatSession) -> Bool {
        if session.id == draftSession.id {
            return !session.messages.isEmpty
        }
        return true
    }

    private func promoteDraftIfNeeded(_ session: ChatSession) {
        guard session.id == draftSession.id else { return }
        draftSession = ChatSession()
    }

    private func ensureValidSelection() {
        if let selectedID = selectedSessionID {
            if selectedID == draftSession.id {
                return
            }
            if !chatSessions.contains(where: { $0.id == selectedID }) {
                selectedSessionID = chatSessions.first?.id ?? draftSession.id
            }
        } else {
            selectedSessionID = chatSessions.first?.id ?? draftSession.id
        }
    }
}

// MARK: - Persistence Bridge

extension ChatSessionsViewModel: ChatSessionPersisting {
    func ensureSessionTracked(_ session: ChatSession) {
        guard shouldPersist(session) else { return }
        if chatSessions.contains(where: { $0.id == session.id }) {
            repository.ensureSessionTracked(session)
        } else {
            addSession(session)
        }
    }
}
