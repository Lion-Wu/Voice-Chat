//
//  ChatSessionsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation
import SwiftData
import Combine

enum ChatSessionListPublicationPolicy {
    static func needsPublication(
        current: [ChatSession],
        proposed: [ChatSession]
    ) -> Bool {
        guard current.count == proposed.count else { return true }
        return zip(current, proposed).contains { currentSession, proposedSession in
            currentSession.id != proposedSession.id || currentSession !== proposedSession
        }
    }
}

struct ChatSearchNavigationTarget: Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let messageID: UUID
    let query: String
    let anchorY: Double

    init(sessionID: UUID, messageID: UUID, query: String, anchorY: Double) {
        self.id = UUID()
        self.sessionID = sessionID
        self.messageID = messageID
        self.query = query
        self.anchorY = anchorY
    }
}

struct ChatSessionPersistenceWriteFailure: Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
final class ChatSessionsViewModel: ObservableObject {
    private struct PendingOrderingUpdate {
        let session: ChatSession
        let shouldPromoteDraft: Bool
    }

    // MARK: - Published State
    @Published private(set) var chatSessions: [ChatSession] = []
    @Published private(set) var draftSession: ChatSession = ChatSession()
    @Published private(set) var searchNavigationTarget: ChatSearchNavigationTarget? = nil
    @Published var selectedSessionID: UUID? = nil {
        didSet {
            guard oldValue != selectedSessionID else { return }
            scheduleSearchNavigationTargetValidation()
        }
    }
    @Published private(set) var isRealtimeVoiceLocked: Bool = false
    @Published private(set) var hasActiveTextRequests: Bool = false
    @Published private(set) var isPersistentStoreAttached: Bool = false
    @Published private(set) var persistenceWriteFailure: ChatSessionPersistenceWriteFailure?
    /// Content-only mutations do not need to replace the session array, but
    /// sidebar search and time grouping still need to recompute their derived
    /// membership.
    let sidebarContentDidChange = PassthroughSubject<Void, Never>()

    // MARK: - Cached View Models
    private var viewModelCache: [UUID: ChatViewModel] = [:]
    private var activityCancellables: [UUID: AnyCancellable] = [:]
    private var sessionsWithActiveTextRequests: Set<UUID> = []
    private var textActivityPublishTask: Task<Void, Never>?
    private var searchNavigationTargetValidationTask: Task<Void, Never>?
    private var pendingOrderingUpdates: [UUID: PendingOrderingUpdate] = [:]
    private var orderingPublishTask: Task<Void, Never>?
    private var sidebarSummaryBackfillTask: Task<Void, Never>?
    private var deletedSessionIDs: Set<UUID> = []
    private var sidebarPresentation = ChatSidebarPresentationController()
    var onPersistentStoreReadFailure: ((Error) -> Void)?

    // MARK: - Dependencies
    private let settingsManager: SettingsManager
    private let runtimeConfigurationResolver: ChatRuntimeConfigurationResolver
    private let reachability: ServerReachabilityMonitor
    private let audioManager: GlobalAudioManager
    private let chatServiceFactory: (ChatServiceConfiguring) -> ChatStreamingService
    private let repository: ChatSessionRepository
    private var cachedChatConfiguration: ChatServiceConfiguration
    private var configurationUpdateTask: Task<Void, Never>?

    // MARK: - Init
    init(
        settingsManager: SettingsManager,
        reachability: ServerReachabilityMonitor,
        audioManager: GlobalAudioManager,
        chatServiceFactory: @escaping (ChatServiceConfiguring) -> ChatStreamingService = { ChatService(configurationProvider: $0) },
        repository: ChatSessionRepository? = nil
    ) {
        let resolvedRuntimeConfiguration = ChatRuntimeConfigurationResolver(settingsManager: settingsManager)
        self.settingsManager = settingsManager
        self.runtimeConfigurationResolver = resolvedRuntimeConfiguration
        self.reachability = reachability
        self.audioManager = audioManager
        self.chatServiceFactory = chatServiceFactory
        self.repository = repository ?? SwiftDataChatSessionRepository()
        self.cachedChatConfiguration = resolvedRuntimeConfiguration.currentConfiguration()
        self.repository.didPersistSessions = { [weak self] sessionIDs in
            self?.handlePersistedSessions(sessionIDs)
        }
        self.selectedSessionID = draftSession.id
    }

    private func currentChatConfiguration() -> ChatServiceConfiguration {
        runtimeConfigurationResolver.currentConfiguration()
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
        isPersistentStoreAttached && !isRealtimeVoiceLocked
    }

    func clearPersistenceWriteFailure() {
        persistenceWriteFailure = nil
    }

    func sessions(matchingSidebarQuery rawQuery: String) -> [ChatSession] {
        sidebarPresentation.sessions(matching: rawQuery, in: chatSessions)
    }

    func normalizedSidebarSearchQuery(_ rawQuery: String) -> String {
        sidebarPresentation.normalizedQuery(rawQuery)
    }

    func sessions(
        in candidateSessions: [ChatSession],
        matchingNormalizedSidebarQuery normalizedQuery: String
    ) -> [ChatSession] {
        sidebarPresentation.sessions(candidateSessions, matchingNormalizedQuery: normalizedQuery)
    }

    func sidebarSubtitle(for session: ChatSession) -> String {
        sidebarPresentation.subtitle(for: session)
    }

    func sidebarPreview(for session: ChatSession, matchingSearchQuery rawQuery: String) -> SidebarSessionPreview {
        sidebarPresentation.preview(for: session, matchingSearchQuery: rawQuery)
    }

    func selectSession(_ session: ChatSession, matchingSidebarQuery rawQuery: String? = nil) {
        selectedSession = session
        configureSearchNavigationTarget(for: session, rawQuery: rawQuery)
    }

    private func scheduleSearchNavigationTargetValidation() {
        searchNavigationTargetValidationTask?.cancel()
        searchNavigationTargetValidationTask = Task { @MainActor [weak self] in
            // `selectedSessionID` can be driven by `List(selection:)` during a
            // SwiftUI update pass. Defer any secondary publish until that pass ends.
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            guard let target = self.searchNavigationTarget,
                  target.sessionID != self.selectedSessionID else {
                return
            }
            self.searchNavigationTarget = nil
        }
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
            if cached.chatSession !== session {
                repository.hydrateTransientMessageState(in: session)
            }
            cached.attach(session: session)
            bindActivity(for: cached, sessionID: session.id)
            return cached
        }
        repository.hydrateTransientMessageState(in: session)
        let vm = ChatViewModel(
            chatSession: session,
            settingsManager: settingsManager,
            reachability: reachability,
            audioManager: audioManager,
            chatService: nil,
            chatServiceFactory: chatServiceFactory,
            sessionPersistence: self
        )
        viewModelCache[session.id] = vm
        bindActivity(for: vm, sessionID: session.id)
        return vm
    }

    // MARK: - Attach Context
    @discardableResult
    func attach(context: ModelContext) -> Bool {
        repository.attach(context: context)
        let didLoad = loadChatSessions()
        if !didLoad {
            repository.detach()
        }
        isPersistentStoreAttached = didLoad
        return didLoad
    }

    func detachPersistentStore() {
        // Stop persistence first so cancelling active requests cannot write an
        // interruption record back into the store that is about to be erased.
        repository.detach()
        isPersistentStoreAttached = false
        sidebarSummaryBackfillTask?.cancel()
        sidebarSummaryBackfillTask = nil
        orderingPublishTask?.cancel()
        orderingPublishTask = nil
        configurationUpdateTask?.cancel()
        configurationUpdateTask = nil
        searchNavigationTargetValidationTask?.cancel()
        searchNavigationTargetValidationTask = nil
        textActivityPublishTask?.cancel()
        textActivityPublishTask = nil
        viewModelCache.values.forEach {
            $0.cancelCurrentRequest(autostartQueuedDraft: false)
        }
        activityCancellables.values.forEach { $0.cancel() }
        activityCancellables.removeAll()
        viewModelCache.removeAll()
        sessionsWithActiveTextRequests.removeAll()
        pendingOrderingUpdates.removeAll()
        deletedSessionIDs.removeAll()
        sidebarPresentation = ChatSidebarPresentationController()
        chatSessions = []
        draftSession = ChatSession()
        selectedSessionID = draftSession.id
        searchNavigationTarget = nil
        hasActiveTextRequests = false
        persistenceWriteFailure = nil
    }

    // MARK: - Session Ops
    func startNewSession() {
        guard canStartNewSession else { return }
        searchNavigationTarget = nil
        selectedSessionID = draftSession.id
    }

    private func cacheViewModel(for session: ChatSession) {
        ensureChatConfigurationCurrent()
        if let existing = viewModelCache[session.id] {
            if existing.chatSession !== session {
                repository.hydrateTransientMessageState(in: session)
            }
            existing.attach(session: session)
            viewModelCache[session.id] = existing
            bindActivity(for: existing, sessionID: session.id)
            return
        }

        repository.hydrateTransientMessageState(in: session)
        let vm = ChatViewModel(
            chatSession: session,
            settingsManager: settingsManager,
            reachability: reachability,
            audioManager: audioManager,
            chatService: nil,
            chatServiceFactory: chatServiceFactory,
            sessionPersistence: self
        )
        viewModelCache[session.id] = vm
        bindActivity(for: vm, sessionID: session.id)
    }

    func addSession(_ session: ChatSession) {
        trackNewSession(session)
        persist(session: session, reason: .immediate)
    }

    private func trackNewSession(_ session: ChatSession) {
        ensureChatConfigurationCurrent()
        deletedSessionIDs.remove(session.id)
        repository.ensureSessionTracked(session)
        cacheViewModel(for: session)
        searchNavigationTarget = nil
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
        _ = loadChatSessions() // Keeps list in sync with persisted state.
    }

    // MARK: - Persistence (SwiftData)
    @discardableResult
    func persist(session: ChatSession, reason: SessionPersistReason = .throttled) -> Bool {
        guard shouldPersist(session) else { return false }
        invalidateSidebarPresentationCache(for: session.id)
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
    @discardableResult
    func loadChatSessions() -> Bool {
        do {
            let fetched = try repository.fetchSessions()
            chatSessions = orderedSessions(fetched)
            pruneStaleViewModels(keeping: fetched)
            ensureChatConfigurationCurrent()
            ensureValidSelection()
            scheduleSidebarSummaryBackfillIfNeeded(in: fetched)
            return true
        } catch {
            onPersistentStoreReadFailure?(error)
            return false
        }
    }

    private func pruneStaleViewModels(keeping sessions: [ChatSession]) {
        let validIDs = Set(sessions.map(\.id)).union([draftSession.id])
        let staleKeys = viewModelCache.keys.filter { !validIDs.contains($0) }
        for key in staleKeys {
            viewModelCache.removeValue(forKey: key)
            unbindActivity(for: key)
        }

        sidebarPresentation.prune(keeping: validIDs)
    }

    private func scheduleSidebarSummaryBackfillIfNeeded(in sessions: [ChatSession]) {
        sidebarSummaryBackfillTask?.cancel()
        let sessionsNeedingBackfill = sessions.filter { $0.sidebarPreviewText == nil }
        guard !sessionsNeedingBackfill.isEmpty else {
            sidebarSummaryBackfillTask = nil
            return
        }

        sidebarSummaryBackfillTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // A cancelled predecessor must not clear the handle of the
                // newer backfill task that replaced it.
                if !Task.isCancelled {
                    self.sidebarSummaryBackfillTask = nil
                }
            }
            var didBackfillAnySummary = false
            var readFailure: Error?
            for session in sessionsNeedingBackfill {
                if Task.isCancelled { break }
                guard !self.deletedSessionIDs.contains(session.id) else { continue }

                do {
                    if try self.repository.backfillSidebarSummaryIfNeeded(for: session) {
                        didBackfillAnySummary = true
                        self.invalidateSidebarPresentationCache(for: session.id)
                        self.updateInMemoryOrdering(with: session)
                    }
                } catch {
                    readFailure = error
                    break
                }

                // Give the already-published sidebar a chance to display each
                // completed legacy summary before fetching the next one.
                await Task.yield()
            }

            guard !Task.isCancelled else { return }
            if didBackfillAnySummary {
                do {
                    try self.repository.saveSidebarSummaryBackfills()
                } catch {
                    guard !Task.isCancelled else { return }
                    self.persistenceWriteFailure = ChatSessionPersistenceWriteFailure(
                        message: error.localizedDescription
                    )
                    return
                }
            }
            guard !Task.isCancelled else { return }
            if let readFailure {
                self.onPersistentStoreReadFailure?(readFailure)
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

        let reordered = orderedSessions(updated)
        if ChatSessionListPublicationPolicy.needsPublication(
            current: chatSessions,
            proposed: reordered
        ) {
            chatSessions = reordered
        } else {
            sidebarContentDidChange.send(())
        }
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

    private func invalidateSidebarPresentationCache(for sessionID: UUID) {
        sidebarPresentation.invalidate(for: sessionID)
    }

    private func configureSearchNavigationTarget(for session: ChatSession, rawQuery: String?) {
        let query = rawQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedQuery = normalizedSidebarSearchQuery(query)
        guard !normalizedQuery.isEmpty,
              let match = sidebarPresentation.bodySearchMatch(
                  in: session,
                  rawQuery: query,
                  matchingNormalizedQuery: normalizedQuery
              ) else {
            searchNavigationTarget = nil
            return
        }

        searchNavigationTarget = ChatSearchNavigationTarget(
            sessionID: session.id,
            messageID: match.messageID,
            query: query,
            anchorY: match.anchorY
        )
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
            // The mutation controller persists immediately after this call.
            // Tracking must not issue its own save or the first draft mutation
            // would write the same session twice.
            trackNewSession(session)
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
