//
//  ChatSessionsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class ChatSessionsViewModel: ObservableObject {
    private struct PendingOrderingUpdate {
        let session: ChatSession
        let shouldPromoteDraft: Bool
    }

    private struct SidebarPresentationCacheEntry {
        let title: String
        let messageCount: Int
        let lastMessageID: UUID?
        let lastMessageContent: String?
        let subtitle: String
        let searchCorpus: String?
    }

    // MARK: - Published State
    @Published private(set) var chatSessions: [ChatSession] = []
    @Published private(set) var draftSession: ChatSession = ChatSession()
    @Published var selectedSessionID: UUID? = nil
    @Published private(set) var isRealtimeVoiceLocked: Bool = false
    @Published private(set) var hasActiveTextRequests: Bool = false

    // MARK: - Cached View Models
    private var viewModelCache: [UUID: ChatViewModel] = [:]
    private var activityCancellables: [UUID: AnyCancellable] = [:]
    private var sessionsWithActiveTextRequests: Set<UUID> = []
    private var textActivityPublishTask: Task<Void, Never>?
    private var pendingOrderingUpdates: [UUID: PendingOrderingUpdate] = [:]
    private var orderingPublishTask: Task<Void, Never>?
    private var deletedSessionIDs: Set<UUID> = []
    private var sidebarPresentationCache: [UUID: SidebarPresentationCacheEntry] = [:]

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
            apiKey: self.settingsManager.chatSettings.apiKey,
            providerHint: self.settingsManager.resolvedChatProvider(for: self.settingsManager.chatSettings.apiURL),
            requestStyleHint: self.settingsManager.resolvedChatRequestStyle(for: self.settingsManager.chatSettings.apiURL),
            thinkingCapability: self.settingsManager.thinkingCapability(for: self.settingsManager.chatSettings.selectedModel),
            thinkingOption: self.settingsManager.selectedThinkingOption(for: self.settingsManager.chatSettings.selectedModel),
            apiAdvancedSettings: self.settingsManager.activeAPIAdvancedSettings
        )
        self.repository.didPersistSessions = { [weak self] sessionIDs in
            self?.handlePersistedSessions(sessionIDs)
        }
        self.selectedSessionID = draftSession.id
    }

    private func currentChatConfiguration() -> ChatServiceConfiguration {
        ChatServiceConfiguration(
            apiBaseURL: settingsManager.chatSettings.apiURL,
            modelIdentifier: settingsManager.chatSettings.selectedModel,
            apiKey: settingsManager.chatSettings.apiKey,
            providerHint: settingsManager.resolvedChatProvider(for: settingsManager.chatSettings.apiURL),
            requestStyleHint: settingsManager.resolvedChatRequestStyle(for: settingsManager.chatSettings.apiURL),
            thinkingCapability: settingsManager.thinkingCapability(for: settingsManager.chatSettings.selectedModel),
            thinkingOption: settingsManager.selectedThinkingOption(for: settingsManager.chatSettings.selectedModel),
            apiAdvancedSettings: settingsManager.activeAPIAdvancedSettings
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

    func sessions(matchingSidebarQuery rawQuery: String) -> [ChatSession] {
        let normalizedQuery = normalizedSidebarSearchQuery(rawQuery)
        guard !normalizedQuery.isEmpty else { return chatSessions }

        return chatSessions.filter { session in
            sidebarSearchCorpus(for: session).contains(normalizedQuery)
        }
    }

    func sidebarSubtitle(for session: ChatSession) -> String {
        sidebarPresentation(for: session).subtitle
    }

    func cancelAllActiveTextRequests(autostartQueuedDrafts: Bool = true) {
        viewModelCache.values.forEach { $0.cancelCurrentRequest(autostartQueuedDraft: autostartQueuedDrafts) }
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
            bindActivity(for: cached, sessionID: session.id)
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
        bindActivity(for: vm, sessionID: session.id)
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
            bindActivity(for: existing, sessionID: session.id)
            return
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
        bindActivity(for: vm, sessionID: session.id)
    }

    func addSession(_ session: ChatSession) {
        ensureChatConfigurationCurrent()
        deletedSessionIDs.remove(session.id)
        repository.ensureSessionTracked(session)
        cacheViewModel(for: session)
        persist(session: session, reason: .immediate)
        selectedSessionID = session.id
    }

    func renameSession(_ session: ChatSession, to newTitle: String, reason: SessionPersistReason = .immediate) {
        session.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        persist(session: session, reason: reason)
    }

    func deleteSession(at offsets: IndexSet) {
        for index in offsets {
            let s = chatSessions[index]
            deletedSessionIDs.insert(s.id)
            pendingOrderingUpdates.removeValue(forKey: s.id)
            viewModelCache.removeValue(forKey: s.id)
            unbindActivity(for: s.id)
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
            // Delayed repository saves are observed via `didPersistSessions`; this path
            // only handles writes that landed synchronously with the caller.
            let shouldPromoteDraft = session.id == draftSession.id
            scheduleInMemoryOrderingUpdate(with: session, shouldPromoteDraft: shouldPromoteDraft)
        }
        return didPersist
    }

    // MARK: - Fetch
    func loadChatSessions() {
        let fetched = repository.fetchSessions()
        hydrateLastMessageActivityIfNeeded(in: fetched)
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
            unbindActivity(for: key)
        }

        let staleSidebarKeys = sidebarPresentationCache.keys.filter { !validIDs.contains($0) }
        for key in staleSidebarKeys {
            sidebarPresentationCache.removeValue(forKey: key)
        }
    }

    private func hydrateLastMessageActivityIfNeeded(in sessions: [ChatSession]) {
        for session in sessions where session.lastMessageAt == nil {
            if let latest = session.messages.lazy.map(\.createdAt).max() {
                session.lastMessageAt = latest
            }
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

    private func scheduleInMemoryOrderingUpdate(with session: ChatSession, shouldPromoteDraft: Bool) {
        guard !deletedSessionIDs.contains(session.id) else { return }
        if let existing = pendingOrderingUpdates[session.id] {
            pendingOrderingUpdates[session.id] = PendingOrderingUpdate(
                session: session,
                shouldPromoteDraft: existing.shouldPromoteDraft || shouldPromoteDraft
            )
        } else {
            pendingOrderingUpdates[session.id] = PendingOrderingUpdate(
                session: session,
                shouldPromoteDraft: shouldPromoteDraft
            )
        }
        orderingPublishTask?.cancel()
        orderingPublishTask = Task { @MainActor [weak self] in
            // Publish outside the current update stack to avoid SwiftUI runtime warnings.
            await Task.yield()
            guard let self, !Task.isCancelled else { return }

            let pending = Array(self.pendingOrderingUpdates.values)
            self.pendingOrderingUpdates.removeAll()

            guard !pending.isEmpty else { return }
            for update in pending {
                guard !self.deletedSessionIDs.contains(update.session.id) else { continue }
                self.updateInMemoryOrdering(with: update.session)
                if update.shouldPromoteDraft {
                    self.promoteDraftIfNeeded(update.session)
                }
            }
        }
    }

    func updateRealtimeVoiceLock(_ active: Bool) {
        if isRealtimeVoiceLocked != active {
            isRealtimeVoiceLocked = active
        }
    }

    private func orderedSessions(_ sessions: [ChatSession]) -> [ChatSession] {
        let activityDates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.lastActivityAt) })
        return sessions.sorted { lhs, rhs in
            let lhsActivity = activityDates[lhs.id] ?? lhs.updatedAt
            let rhsActivity = activityDates[rhs.id] ?? rhs.updatedAt
            if lhsActivity == rhsActivity {
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
            return lhsActivity > rhsActivity
        }
    }

    private func normalizedSidebarSearchQuery(_ rawQuery: String) -> String {
        rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func sidebarPresentation(for session: ChatSession) -> SidebarPresentationCacheEntry {
        let lastMessage = session.messages.max(by: { $0.createdAt < $1.createdAt })
        let lastMessageContent = lastMessage?.content

        if let cached = sidebarPresentationCache[session.id],
           cached.title == session.title,
           cached.messageCount == session.messages.count,
           cached.lastMessageID == lastMessage?.id,
           cached.lastMessageContent == lastMessageContent {
            return cached
        }

        let bodyText = lastMessageContent?
            .extractThinkParts()
            .body
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let subtitle: String
        if lastMessage == nil {
            subtitle = "Fresh conversation"
        } else if bodyText.isEmpty {
            subtitle = "No recent replies"
        } else {
            let snippet = bodyText.prefix(60)
            subtitle = bodyText.count > 60 ? "\(snippet)…" : String(snippet)
        }

        let entry = SidebarPresentationCacheEntry(
            title: session.title,
            messageCount: session.messages.count,
            lastMessageID: lastMessage?.id,
            lastMessageContent: lastMessageContent,
            subtitle: subtitle,
            searchCorpus: nil
        )
        sidebarPresentationCache[session.id] = entry
        return entry
    }

    private func sidebarSearchCorpus(for session: ChatSession) -> String {
        let presentation = sidebarPresentation(for: session)
        if let cachedCorpus = presentation.searchCorpus {
            return cachedCorpus
        }

        let searchCorpus = ([session.title] + session.messages.map(\.content))
            .joined(separator: "\n")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let updatedEntry = SidebarPresentationCacheEntry(
            title: presentation.title,
            messageCount: presentation.messageCount,
            lastMessageID: presentation.lastMessageID,
            lastMessageContent: presentation.lastMessageContent,
            subtitle: presentation.subtitle,
            searchCorpus: searchCorpus
        )
        sidebarPresentationCache[session.id] = updatedEntry
        return searchCorpus
    }

    private func shouldPersist(_ session: ChatSession) -> Bool {
        if session.id == draftSession.id {
            return !session.messages.isEmpty
        }
        return true
    }

    private func handlePersistedSessions(_ sessionIDs: Set<UUID>) {
        for sessionID in sessionIDs {
            guard !deletedSessionIDs.contains(sessionID) else { continue }
            guard let session = sessionForPersistedID(sessionID) else { continue }
            scheduleInMemoryOrderingUpdate(
                with: session,
                shouldPromoteDraft: session.id == draftSession.id
            )
        }
    }

    private func sessionForPersistedID(_ sessionID: UUID) -> ChatSession? {
        if draftSession.id == sessionID {
            return draftSession
        }
        if let session = chatSessions.first(where: { $0.id == sessionID }) {
            return session
        }
        return viewModelCache[sessionID]?.chatSession
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

    // MARK: - Activity tracking

    private func bindActivity(for viewModel: ChatViewModel, sessionID: UUID) {
        activityCancellables[sessionID]?.cancel()

        // Seed the current state so `hasActiveTextRequests` is correct even before the first emission.
        setTextRequestActive(viewModel.isLoading || viewModel.isPriming, for: sessionID)

        let cancellable = Publishers.CombineLatest(viewModel.$isLoading, viewModel.$isPriming)
            .map { isLoading, isPriming in isLoading || isPriming }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                self?.setTextRequestActive(active, for: sessionID)
            }

        activityCancellables[sessionID] = cancellable
    }

    private func unbindActivity(for sessionID: UUID) {
        activityCancellables[sessionID]?.cancel()
        activityCancellables.removeValue(forKey: sessionID)
        setTextRequestActive(false, for: sessionID)
    }

    private func setTextRequestActive(_ active: Bool, for sessionID: UUID) {
        if active {
            sessionsWithActiveTextRequests.insert(sessionID)
        } else {
            sessionsWithActiveTextRequests.remove(sessionID)
        }

        scheduleTextActivityPublish()
    }

    private func scheduleTextActivityPublish() {
        textActivityPublishTask?.cancel()
        textActivityPublishTask = Task { @MainActor [weak self] in
            // Publish outside the current update stack to avoid SwiftUI's
            // "Publishing changes from within view updates" runtime warning.
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            let nowActive = !self.sessionsWithActiveTextRequests.isEmpty
            if self.hasActiveTextRequests != nowActive {
                self.hasActiveTextRequests = nowActive
            }
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

    func flushPendingSaves() {
        repository.flushPendingSaves()
    }

    func setImmediatePersistenceEnabled(_ enabled: Bool) {
        repository.setImmediatePersistenceEnabled(enabled)
    }
}

extension ChatSessionsViewModel: ChatSessionActivityPublishing {
    func publishLiveActivity(for session: ChatSession) {
        guard shouldPersist(session) else { return }
        guard session.id != draftSession.id || pendingOrderingUpdates[session.id] != nil else { return }
        scheduleInMemoryOrderingUpdate(with: session, shouldPromoteDraft: false)
    }
}
