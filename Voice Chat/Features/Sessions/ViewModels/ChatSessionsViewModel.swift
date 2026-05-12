//
//  ChatSessionsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation
import SwiftData
import Combine

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

struct SidebarSessionPreview: Equatable {
    let text: String
    let emphasizedRanges: [NSRange]

    static func plain(_ text: String) -> SidebarSessionPreview {
        SidebarSessionPreview(text: text, emphasizedRanges: [])
    }
}

@MainActor
final class ChatSessionsViewModel: ObservableObject {
    private struct PendingOrderingUpdate {
        let session: ChatSession
        let shouldPromoteDraft: Bool
    }

    private struct SidebarSearchBodyMatch {
        let messageID: UUID
        let bodyText: String
        let foundRange: NSRange?
        let anchorY: Double
    }

    private struct SidebarPresentationCacheEntry {
        let title: String
        let messageCount: Int
        let lastMessageAt: Date?
        let lastMessageID: UUID?
        let lastMessageContent: String?
        let subtitle: String
        let searchCorpus: String?
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

    // MARK: - Cached View Models
    private var viewModelCache: [UUID: ChatViewModel] = [:]
    private var activityCancellables: [UUID: AnyCancellable] = [:]
    private var sessionsWithActiveTextRequests: Set<UUID> = []
    private var textActivityPublishTask: Task<Void, Never>?
    private var searchNavigationTargetValidationTask: Task<Void, Never>?
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

    func normalizedSidebarSearchQuery(_ rawQuery: String) -> String {
        normalizedSidebarSearchText(rawQuery.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func normalizedSidebarSearchText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    func sessions(
        in candidateSessions: [ChatSession],
        matchingNormalizedSidebarQuery normalizedQuery: String
    ) -> [ChatSession] {
        guard !normalizedQuery.isEmpty else { return candidateSessions }
        return candidateSessions.filter { session in
            sidebarSearchCorpus(for: session).contains(normalizedQuery)
        }
    }

    func sidebarSubtitle(for session: ChatSession) -> String {
        sidebarPresentation(for: session).subtitle
    }

    func sidebarPreview(for session: ChatSession, matchingSearchQuery rawQuery: String) -> SidebarSessionPreview {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = normalizedSidebarSearchQuery(query)
        guard !normalizedQuery.isEmpty,
              let match = sidebarBodySearchMatch(
                  in: session,
                  rawQuery: query,
                  matchingNormalizedSidebarQuery: normalizedQuery
              ),
              let preview = sidebarSearchContextPreview(
                  in: match.bodyText,
                  query: query,
                  foundRange: match.foundRange
              ) else {
            return .plain(sidebarSubtitle(for: session))
        }

        return preview
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
        searchNavigationTarget = nil
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
        loadChatSessions() // Keeps list in sync with persisted state.
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

    private func invalidateSidebarPresentationCache(for sessionID: UUID) {
        sidebarPresentationCache.removeValue(forKey: sessionID)
    }

    private func latestSidebarMessage(in session: ChatSession) -> ChatMessage? {
        if let lastMessageAt = session.lastMessageAt,
           let message = session.messages.first(where: { $0.createdAt == lastMessageAt }) {
            return message
        }
        return session.messages.max(by: { $0.createdAt < $1.createdAt })
    }

    private func sidebarSearchText(for message: ChatMessage) -> String {
        message.content.extractThinkParts().body
    }

    private func sidebarSearchMessages(in session: ChatSession) -> [ChatMessage] {
        activeSidebarBranchMessages(in: session)
    }

    private func activeSidebarBranchMessages(in session: ChatSession) -> [ChatMessage] {
        let lookup = sidebarMessageLookup(in: session)
        let childrenByParent = sidebarChildrenByParent(in: session)
        guard let root = activeSidebarRootMessage(in: session, lookup: lookup) else {
            return []
        }

        var out: [ChatMessage] = []
        out.reserveCapacity(min(64, session.messages.count))

        var visited = Set<UUID>()
        var current: ChatMessage? = root
        while let message = current, visited.insert(message.id).inserted {
            out.append(message)
            guard let next = activeSidebarChild(
                for: message,
                lookup: lookup,
                childrenByParent: childrenByParent
            ) else {
                break
            }
            current = next
        }

        return out
    }

    private func sidebarMessageLookup(in session: ChatSession) -> [UUID: ChatMessage] {
        var lookup: [UUID: ChatMessage] = [:]
        lookup.reserveCapacity(session.messages.count)
        for message in session.messages {
            lookup[message.id] = message
        }
        return lookup
    }

    private func sidebarChildrenByParent(in session: ChatSession) -> [UUID: [ChatMessage]] {
        var childrenByParent: [UUID: [ChatMessage]] = [:]
        childrenByParent.reserveCapacity(session.messages.count)
        for message in session.messages {
            if let parent = message.parentMessage {
                childrenByParent[parent.id, default: []].append(message)
            }
        }
        return childrenByParent
    }

    private func activeSidebarRootMessage(
        in session: ChatSession,
        lookup: [UUID: ChatMessage]
    ) -> ChatMessage? {
        if let id = session.activeRootMessageID,
           let active = lookup[id] {
            return sidebarRootMessage(for: active, lookup: lookup)
        }

        if let root = session.messages
            .filter({ $0.parentMessage == nil })
            .sorted(by: stableSidebarMessageOrder)
            .first {
            return root
        }

        return session.messages.sorted(by: stableSidebarMessageOrder).first
    }

    private func activeSidebarChild(
        for message: ChatMessage,
        lookup: [UUID: ChatMessage],
        childrenByParent: [UUID: [ChatMessage]]
    ) -> ChatMessage? {
        let children = childrenByParent[message.id, default: []].sorted(by: stableSidebarMessageOrder)
        guard !children.isEmpty else { return nil }

        if let activeChildID = message.activeChildMessageID,
           let activeChild = lookup[activeChildID],
           activeChild.parentMessage?.id == message.id {
            return activeChild
        }

        return children.last
    }

    private func sidebarRootMessage(
        for message: ChatMessage,
        lookup: [UUID: ChatMessage]
    ) -> ChatMessage {
        var cursor = message
        var visited = Set<UUID>()
        while let parent = cursor.parentMessage,
              lookup[parent.id] != nil,
              visited.insert(cursor.id).inserted {
            cursor = parent
        }
        return cursor
    }

    private func stableSidebarMessageOrder(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func sidebarBodySearchMatch(
        in session: ChatSession,
        rawQuery: String,
        matchingNormalizedSidebarQuery normalizedQuery: String
    ) -> SidebarSearchBodyMatch? {
        guard !normalizedQuery.isEmpty else { return nil }

        for message in sidebarSearchMessages(in: session) {
            let body = sidebarSearchText(for: message)
            let normalizedBody = normalizedSidebarSearchText(body)
            if normalizedBody.contains(normalizedQuery) {
                let foundRange = sidebarSearchRange(in: body, query: rawQuery)
                return SidebarSearchBodyMatch(
                    messageID: message.id,
                    bodyText: body,
                    foundRange: foundRange,
                    anchorY: searchAnchorY(in: body, foundRange: foundRange)
                )
            }
        }

        return nil
    }

    private func sidebarSearchRange(in text: String, query: String) -> NSRange? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let foundRange = nsText.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: NSRange(location: 0, length: nsText.length)
        )
        guard foundRange.location != NSNotFound, foundRange.length > 0 else { return nil }
        return foundRange
    }

    private func searchAnchorY(in text: String, foundRange: NSRange?) -> Double {
        let nsText = text as NSString
        guard nsText.length > 0,
              let foundRange,
              foundRange.location != NSNotFound,
              foundRange.length > 0 else {
            return 0.5
        }

        let midpoint = Double(foundRange.location) + Double(foundRange.length) / 2
        if let lineAnchor = searchLineAnchorY(in: text, foundRange: foundRange) {
            return lineAnchor
        }
        return clampedSearchAnchorY(midpoint / Double(nsText.length))
    }

    private func searchLineAnchorY(in text: String, foundRange: NSRange) -> Double? {
        guard text.contains(where: \.isNewline),
              let range = Range(foundRange, in: text) else {
            return nil
        }

        let lineIndex = text[..<range.lowerBound].reduce(0) { partial, character in
            partial + (character.isNewline ? 1 : 0)
        }
        let lineCount = text.reduce(1) { partial, character in
            partial + (character.isNewline ? 1 : 0)
        }
        guard lineCount > 1 else { return nil }
        return clampedSearchAnchorY((Double(lineIndex) + 0.5) / Double(lineCount))
    }

    private func clampedSearchAnchorY(_ anchorY: Double) -> Double {
        min(0.95, max(0.05, anchorY))
    }

    private func sidebarSearchContextPreview(
        in text: String,
        query: String,
        foundRange: NSRange?
    ) -> SidebarSessionPreview? {
        guard let foundRange,
              let range = Range(foundRange, in: text) else {
            return nil
        }

        let leadingContextLength = 8
        let trailingContextLength = 64
        let contextStart = text.index(
            range.lowerBound,
            offsetBy: -leadingContextLength,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        let contextEnd = text.index(
            range.upperBound,
            offsetBy: trailingContextLength,
            limitedBy: text.endIndex
        ) ?? text.endIndex

        var snippet = String(text[contextStart..<contextEnd])
        snippet = singleLineSidebarSnippet(snippet).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty else { return nil }

        if contextStart > text.startIndex {
            snippet = "…" + snippet
        }
        if contextEnd < text.endIndex {
            snippet += "…"
        }

        let emphasizedRanges = sidebarSearchRanges(in: snippet, query: query)
        return SidebarSessionPreview(text: snippet, emphasizedRanges: emphasizedRanges)
    }

    private func singleLineSidebarSnippet(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func sidebarSearchRanges(in text: String, query: String) -> [NSRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let foundRange = nsText.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard foundRange.location != NSNotFound, foundRange.length > 0 else { break }

            ranges.append(foundRange)
            let nextLocation = foundRange.location + foundRange.length
            searchRange = NSRange(location: nextLocation, length: max(0, nsText.length - nextLocation))
        }
        return ranges
    }

    private func configureSearchNavigationTarget(for session: ChatSession, rawQuery: String?) {
        let query = rawQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedQuery = normalizedSidebarSearchQuery(query)
        guard !normalizedQuery.isEmpty,
              let match = sidebarBodySearchMatch(
                  in: session,
                  rawQuery: query,
                  matchingNormalizedSidebarQuery: normalizedQuery
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

    private func sidebarPresentation(for session: ChatSession) -> SidebarPresentationCacheEntry {
        let lastMessage = latestSidebarMessage(in: session)
        let lastMessageContent = lastMessage?.content

        if let cached = sidebarPresentationCache[session.id],
           cached.title == session.title,
           cached.messageCount == session.messages.count,
           cached.lastMessageID == lastMessage?.id,
           cached.lastMessageContent == lastMessageContent,
           cached.lastMessageAt == session.lastMessageAt {
            return cached
        }

        let bodyText = lastMessageContent?
            .extractThinkParts()
            .body
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let subtitle: String
        if lastMessage == nil {
            subtitle = String(localized: "Fresh conversation")
        } else if bodyText.isEmpty {
            subtitle = String(localized: "No recent replies")
        } else {
            let snippet = bodyText.prefix(60)
            subtitle = bodyText.count > 60 ? "\(snippet)…" : String(snippet)
        }

        let entry = SidebarPresentationCacheEntry(
            title: session.title,
            messageCount: session.messages.count,
            lastMessageAt: session.lastMessageAt,
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

        let messageSearchText = sidebarSearchMessages(in: session).map { sidebarSearchText(for: $0) }
        let searchCorpus = normalizedSidebarSearchText(
            ([session.title] + messageSearchText).joined(separator: "\n")
        )

        let updatedEntry = SidebarPresentationCacheEntry(
            title: presentation.title,
            messageCount: presentation.messageCount,
            lastMessageAt: presentation.lastMessageAt,
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
