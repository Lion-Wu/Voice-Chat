//
//  ChatViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/18.
//

import Foundation
import Combine

private struct ActiveStreamTelemetry {
    let streamID: UUID
    let startedAt: Date
    let modelIdentifier: String
    let apiBaseURL: String
    let promptMessageCount: Int
    let promptCharacterCount: Int
    var firstTokenAt: Date?
}

@MainActor
final class ChatViewModel: ObservableObject {
    struct MessageContentUpdate: Sendable {
        let messageID: UUID
        let fingerprint: ContentFingerprint
    }

    // MARK: - Published State
    @Published var userMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var isPriming: Bool = false
    @Published var chatSession: ChatSession

    @Published var editingBaseMessageID: UUID? = nil
    var isEditing: Bool { editingBaseMessageID != nil }

    // MARK: - Dependencies
    private var chatService: ChatStreamingService
    private let chatServiceFactory: (ChatServiceConfiguring) -> ChatStreamingService
    private var chatConfiguration: ChatServiceConfiguration
    private let settingsManager: SettingsManager
    private let reachability: ServerReachabilityMonitor
    private let audioManager: GlobalAudioManager
    private weak var sessionPersistence: ChatSessionPersisting?

    private var sending = false

    private var currentAssistantMessageID: UUID?
    private var interruptedAssistantMessageID: UUID?
    private var activeStreamTelemetry: ActiveStreamTelemetry?
    private var pendingDeltaWriteBytes: Int = 0
    private let deltaPersistThreshold: Int = 2048

    // Flag indicating whether the next request should enable realtime narration (set by the voice overlay).
    private var enableRealtimeTTSNext: Bool = false
    // Tracks whether the current assistant response is being streamed in realtime.
    private var realtimeTTSActive: Bool = false
    // Incremental segmenter that ignores `<think>` sections and splits on punctuation.
    private var incSegmenter = IncrementalTextSegmenter()
    // Cached ordering to avoid repeated O(n log n) sorts when rendering long sessions.
    private var orderedMessagesCache: [ChatMessage] = []
    private var orderedMessagesCacheCount: Int = -1
    private var streamingAssistantMessageID: UUID?
    private var streamingAssistantFingerprint: ContentFingerprint?

    // Emits content fingerprint updates (e.g., streaming deltas) to drive targeted UI refreshes.
    let messageContentDidChange = PassthroughSubject<MessageContentUpdate, Never>()

    // MARK: - Init
    init(
        chatSession: ChatSession,
        chatService: ChatStreamingService? = nil,
        chatServiceFactory: ((ChatServiceConfiguring) -> ChatStreamingService)? = nil,
        settingsManager: SettingsManager? = nil,
        reachability: ServerReachabilityMonitor? = nil,
        audioManager: GlobalAudioManager? = nil,
        sessionPersistence: ChatSessionPersisting? = nil
    ) {
        self.chatSession = chatSession
        let resolvedSettings = settingsManager ?? SettingsManager.shared
        self.settingsManager = resolvedSettings
        self.chatConfiguration = ChatServiceConfiguration(
            apiBaseURL: resolvedSettings.chatSettings.apiURL,
            modelIdentifier: resolvedSettings.chatSettings.selectedModel
        )
        self.chatServiceFactory = chatServiceFactory ?? { ChatService(configurationProvider: $0) }
        self.chatService = chatService ?? self.chatServiceFactory(self.chatConfiguration)
        self.reachability = reachability ?? ServerReachabilityMonitor.shared
        self.audioManager = audioManager ?? GlobalAudioManager.shared
        self.sessionPersistence = sessionPersistence

        if chatSession.messages.contains(where: { !$0.isUser && $0.isActive }) {
            self.isLoading = true
        }

        bindChatService(self.chatService)
    }

    // MARK: - Public API for the realtime overlay
    func prepareRealtimeTTSForNextAssistant() {
        enableRealtimeTTSNext = true
    }

    // MARK: - Chat service wiring

    private func bindChatService(_ service: ChatStreamingService) {
        service.onDelta = { [weak self] piece in
            guard let self = self else { return }
            self.handleAssistantDelta(piece)

            if self.realtimeTTSActive {
                let newSegments = self.incSegmenter.append(piece)
                for seg in newSegments where !seg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.audioManager.appendRealtimeSegment(seg)
                }
            }
        }

        service.onError = { [weak self] error in
            guard let self = self else { return }
            self.handleChatServiceError(error)
        }

        service.onStreamFinished = { [weak self] in
            guard let self = self else { return }
            self.handleChatStreamFinished()
        }

        self.chatService = service
    }

    private func handleChatServiceError(_ error: Error) {
        let now = Date()
        let telemetry = activeStreamTelemetry

        isPriming = false
        isLoading = false
        sending = false

        let interrupted = finalizeActiveAssistantMessage(
            reason: "error",
            finishedAt: now,
            errorDescription: error.localizedDescription
        )
        interruptedAssistantMessageID = interrupted?.id
        currentAssistantMessageID = nil
        pendingDeltaWriteBytes = 0

        let firstTokenLatency: TimeInterval?
        if let start = telemetry?.startedAt, let first = telemetry?.firstTokenAt {
            firstTokenLatency = first.timeIntervalSince(start)
        } else {
            firstTokenLatency = nil
        }

        let streamDuration: TimeInterval?
        if let start = telemetry?.startedAt {
            streamDuration = now.timeIntervalSince(start)
        } else {
            streamDuration = nil
        }

        let generationDuration: TimeInterval?
        if let first = telemetry?.firstTokenAt {
            generationDuration = now.timeIntervalSince(first)
        } else {
            generationDuration = nil
        }

        let errContent = "!error:\(error.localizedDescription)"
        let err = ChatMessage(
            content: errContent,
            isUser: false,
            isActive: false,
            createdAt: now,
            modelIdentifier: telemetry?.modelIdentifier ?? chatConfiguration.modelIdentifier,
            apiBaseURL: telemetry?.apiBaseURL ?? chatConfiguration.apiBaseURL,
            requestID: telemetry?.streamID,
            streamStartedAt: telemetry?.startedAt,
            streamFirstTokenAt: telemetry?.firstTokenAt,
            streamCompletedAt: now,
            timeToFirstToken: firstTokenLatency,
            streamDuration: streamDuration,
            generationDuration: generationDuration,
            deltaCount: 1,
            characterCount: errContent.count,
            promptMessageCount: telemetry?.promptMessageCount,
            promptCharacterCount: telemetry?.promptCharacterCount,
            finishReason: "error",
            errorDescription: error.localizedDescription,
            session: chatSession
        )
        chatSession.messages.append(err)
        persistSession(reason: .immediate)

        if realtimeTTSActive {
            audioManager.finishRealtimeStream()
            realtimeTTSActive = false
        }
    }

    private func handleChatStreamFinished() {
        let finishedAt = Date()
        let completedMessage = finalizeActiveAssistantMessage(reason: "completed", finishedAt: finishedAt)
        var candidateFullText: String? = completedMessage?.content
        pendingDeltaWriteBytes = 0

        isPriming = false
        isLoading = false
        sending = false

        if candidateFullText == nil {
            let lastAssistant = chatSession.messages
                .filter { !$0.isUser && !$0.content.hasPrefix("!error:") }
                .sorted(by: { $0.createdAt < $1.createdAt })
                .last
            candidateFullText = lastAssistant?.content
        }

        currentAssistantMessageID = nil
        interruptedAssistantMessageID = nil

        persistSession(reason: .immediate)

        if realtimeTTSActive {
            let tails = incSegmenter.finalize()
            for seg in tails where !seg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                audioManager.appendRealtimeSegment(seg)
            }
            audioManager.finishRealtimeStream()
            realtimeTTSActive = false
        } else if settingsManager.voiceSettings.autoReadAfterGeneration {
            let body = bodyTextForAutoRead(from: candidateFullText ?? "")
            if !body.isEmpty {
                audioManager.startProcessing(text: body)
            }
        }
    }

    /// Rebuilds the chat streaming service when the API base URL or model changes.
    func updateChatConfiguration(_ configuration: ChatServiceConfiguration) {
        guard configuration != chatConfiguration else { return }

        chatService.cancelStreaming()
        finalizeActiveAssistantMessage(reason: "config-changed", finishedAt: Date())
        currentAssistantMessageID = nil

        if realtimeTTSActive {
            audioManager.finishRealtimeStream()
            realtimeTTSActive = false
        }

        if isPriming { isPriming = false }
        if isLoading { isLoading = false }
        if sending { sending = false }
        interruptedAssistantMessageID = nil
        incSegmenter.reset()

        chatConfiguration = configuration
        let newService = chatServiceFactory(configuration)
        bindChatService(newService)
        pendingDeltaWriteBytes = 0
        persistSession(reason: .immediate)
    }

    // MARK: - Helpers (stable ordering & safe trimming)

    private func persistSession(reason: SessionPersistReason = .throttled) {
        sessionPersistence?.ensureSessionTracked(chatSession)
        sessionPersistence?.persist(session: chatSession, reason: reason)
    }

    // MARK: - Telemetry

    private func recordStreamStart(using messages: [ChatMessage]) {
        let eligibleMessages = messages.filter { !$0.content.hasPrefix("!error:") }
        let promptCharacterCount = eligibleMessages.reduce(into: 0) { partial, msg in
            partial += msg.content.count
        }
        pendingDeltaWriteBytes = 0

        activeStreamTelemetry = ActiveStreamTelemetry(
            streamID: UUID(),
            startedAt: Date(),
            modelIdentifier: chatConfiguration.modelIdentifier,
            apiBaseURL: chatConfiguration.apiBaseURL,
            promptMessageCount: eligibleMessages.count,
            promptCharacterCount: promptCharacterCount,
            firstTokenAt: nil
        )
    }

    private func applyStreamMetadata(to message: ChatMessage, firstTokenTimestamp: Date) {
        if var telemetry = activeStreamTelemetry {
            if message.streamStartedAt == nil {
                message.streamStartedAt = telemetry.startedAt
            }
            if message.modelIdentifier == nil {
                message.modelIdentifier = telemetry.modelIdentifier
            }
            if message.apiBaseURL == nil {
                message.apiBaseURL = telemetry.apiBaseURL
            }
            if message.requestID == nil {
                message.requestID = telemetry.streamID
            }
            if message.promptMessageCount == nil {
                message.promptMessageCount = telemetry.promptMessageCount
            }
            if message.promptCharacterCount == nil {
                message.promptCharacterCount = telemetry.promptCharacterCount
            }
            if message.streamFirstTokenAt == nil {
                message.streamFirstTokenAt = firstTokenTimestamp
                telemetry.firstTokenAt = firstTokenTimestamp
                activeStreamTelemetry = telemetry
            }
        } else {
            if message.streamStartedAt == nil {
                message.streamStartedAt = firstTokenTimestamp
            }
            if message.streamFirstTokenAt == nil {
                message.streamFirstTokenAt = firstTokenTimestamp
            }
            if message.modelIdentifier == nil {
                message.modelIdentifier = chatConfiguration.modelIdentifier
            }
            if message.apiBaseURL == nil {
                message.apiBaseURL = chatConfiguration.apiBaseURL
            }
        }
        if let start = message.streamStartedAt,
           let first = message.streamFirstTokenAt,
           message.timeToFirstToken == nil {
            message.timeToFirstToken = first.timeIntervalSince(start)
        }
    }

    private func bumpStreamCounters(for message: ChatMessage, delta: String) {
        message.deltaCount += 1
        message.characterCount += delta.count
        maybePersistStreamDelta(delta.count)
    }

    private func maybePersistStreamDelta(_ addedChars: Int) {
        pendingDeltaWriteBytes += addedChars
        guard pendingDeltaWriteBytes >= deltaPersistThreshold else { return }
        pendingDeltaWriteBytes = 0
        persistSession(reason: .immediate)
    }

    @discardableResult
    private func finalizeActiveAssistantMessage(reason: String, finishedAt: Date = Date(), errorDescription: String? = nil) -> ChatMessage? {
        guard let id = currentAssistantMessageID ?? interruptedAssistantMessageID,
              let message = chatSession.messages.first(where: { $0.id == id }) else {
            activeStreamTelemetry = nil
            return nil
        }

        message.isActive = false
        if message.finishReason == nil {
            message.finishReason = reason
        }
        if message.errorDescription == nil {
            message.errorDescription = errorDescription
        }

        if message.streamStartedAt == nil {
            message.streamStartedAt = activeStreamTelemetry?.startedAt ?? message.createdAt
        }
        if message.modelIdentifier == nil {
            message.modelIdentifier = activeStreamTelemetry?.modelIdentifier ?? chatConfiguration.modelIdentifier
        }
        if message.apiBaseURL == nil {
            message.apiBaseURL = activeStreamTelemetry?.apiBaseURL ?? chatConfiguration.apiBaseURL
        }
        if message.requestID == nil {
            message.requestID = activeStreamTelemetry?.streamID ?? UUID()
        }
        if message.promptMessageCount == nil {
            message.promptMessageCount = activeStreamTelemetry?.promptMessageCount
        }
        if message.promptCharacterCount == nil {
            message.promptCharacterCount = activeStreamTelemetry?.promptCharacterCount
        }
        if message.streamFirstTokenAt == nil, let first = activeStreamTelemetry?.firstTokenAt {
            message.streamFirstTokenAt = first
        }
        if let start = message.streamStartedAt,
           let first = message.streamFirstTokenAt,
           message.timeToFirstToken == nil {
            message.timeToFirstToken = first.timeIntervalSince(start)
        }
        if message.streamCompletedAt == nil {
            message.streamCompletedAt = finishedAt
        }
        if let start = message.streamStartedAt {
            message.streamDuration = message.streamDuration ?? finishedAt.timeIntervalSince(start)
        }
        if let first = message.streamFirstTokenAt {
            message.generationDuration = message.generationDuration ?? finishedAt.timeIntervalSince(first)
        }
        if message.deltaCount == 0 {
            message.deltaCount = 1
        }
        if message.characterCount == 0 {
            message.characterCount = message.content.count
        }

        activeStreamTelemetry = nil
        if streamingAssistantMessageID == message.id {
            streamingAssistantMessageID = nil
            streamingAssistantFingerprint = nil
        }
        return message
    }

    /// Returns messages sorted by time while preserving insertion order for identical timestamps.
    private func chronologicalMessages() -> [ChatMessage] {
        let count = chatSession.messages.count
        if count == orderedMessagesCacheCount && !orderedMessagesCache.isEmpty {
            return orderedMessagesCache
        }

        let sorted = chatSession.messages
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)

        orderedMessagesCache = sorted
        orderedMessagesCacheCount = count
        return sorted
    }

    /// Exposes the cached chronological ordering for UI rendering.
    func orderedMessagesCached() -> [ChatMessage] {
        chronologicalMessages()
    }

    /// Removes the boundary message (if requested) and everything that chronologically follows it.
    private func trimMessages(startingAt boundary: ChatMessage, includeBoundary: Bool) {
        let ordered = chronologicalMessages()
        guard let boundaryIndex = ordered.firstIndex(where: { $0.id == boundary.id }) else { return }

        let keepCount = includeBoundary ? boundaryIndex : boundaryIndex + 1
        let keepIDs = Set(ordered.prefix(keepCount).map(\.id))

        if keepCount == ordered.count {
            return
        }

        chatSession.messages.removeAll { !keepIDs.contains($0.id) }
    }

    // MARK: - Intent

    func sendMessage() {
        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        guard !sending else { return }

        if let baseID = editingBaseMessageID,
           let base = chatSession.messages.first(where: { $0.id == baseID }) {
            trimMessages(startingAt: base, includeBoundary: true)
            editingBaseMessageID = nil
        }

        let userMsg = ChatMessage(
            content: trimmedMessage,
            isUser: true,
            isActive: true,
            createdAt: Date(),
            deltaCount: 1,
            characterCount: trimmedMessage.count,
            session: chatSession
        )
        chatSession.messages.append(userMsg)
        if isPlaceholderTitle(chatSession.title) {
            chatSession.title = trimmedMessage
        }
        persistSession(reason: .immediate)

        // Fail fast if we already know the text server is unreachable.
        if reachability.isChatReachable == false {
            userMessage = ""
            isPriming = false
            isLoading = false
            sending = false
            finalizeActiveAssistantMessage(reason: "aborted-before-send", finishedAt: Date())
            interruptedAssistantMessageID = nil
            currentAssistantMessageID = nil

            let now = Date()
            let errText = NSLocalizedString("Unable to reach the text server. Please check your connection or server settings.", comment: "Shown when sending a message while the text server is unreachable")
            let errContent = "!error:\(errText)"
            let err = ChatMessage(
                content: errContent,
                isUser: false,
                isActive: false,
                createdAt: now,
                modelIdentifier: chatConfiguration.modelIdentifier,
                apiBaseURL: chatConfiguration.apiBaseURL,
                streamStartedAt: now,
                streamCompletedAt: now,
                deltaCount: 1,
                characterCount: errContent.count,
                finishReason: "unreachable",
                session: chatSession
            )
            chatSession.messages.append(err)
            persistSession(reason: .immediate)
            return
        }

        isPriming = true
        isLoading = true
        sending = true
        finalizeActiveAssistantMessage(reason: "superseded", finishedAt: Date())
        interruptedAssistantMessageID = nil
        currentAssistantMessageID = nil
        pendingDeltaWriteBytes = 0
        userMessage = ""
        persistSession(reason: .immediate)

        // Determine whether this response should use realtime narration.
        realtimeTTSActive = enableRealtimeTTSNext
        enableRealtimeTTSNext = false
        if realtimeTTSActive {
            incSegmenter.reset()
            audioManager.startRealtimeStream()
        }

        let currentMessages = chronologicalMessages()
        recordStreamStart(using: currentMessages)
        chatService.fetchStreamedData(messages: currentMessages)
    }

    func cancelCurrentRequest() {
        guard sending || isLoading || isPriming else { return }
        let finishedAt = Date()
        chatService.cancelStreaming()
        finalizeActiveAssistantMessage(reason: "cancelled", finishedAt: finishedAt)
        currentAssistantMessageID = nil
        interruptedAssistantMessageID = nil
        pendingDeltaWriteBytes = 0
        isPriming = false
        isLoading = false
        sending = false
        persistSession(reason: .immediate)

        if realtimeTTSActive {
            audioManager.finishRealtimeStream()
            realtimeTTSActive = false
        }
    }

    private func handleAssistantDelta(_ piece: String) {
        guard isPriming || isLoading || sending else { return }
        objectWillChange.send()

        if isPriming { isPriming = false }
        let now = Date()

        let message: ChatMessage
        let fingerprint: ContentFingerprint
        if let id = currentAssistantMessageID,
           let existing = chatSession.messages.first(where: { $0.id == id }) {
            let previousFingerprint = (streamingAssistantMessageID == existing.id) ? streamingAssistantFingerprint : nil
            existing.content += piece
            message = existing
            if let previousFingerprint {
                fingerprint = previousFingerprint.appending(piece)
            } else {
                fingerprint = ContentFingerprint.make(existing.content)
            }
        } else {
            let sys = ChatMessage(content: piece, isUser: false, isActive: true, createdAt: now, session: chatSession)
            chatSession.messages.append(sys)
            currentAssistantMessageID = sys.id
            message = sys
            fingerprint = ContentFingerprint.make(piece)
        }
        streamingAssistantMessageID = message.id
        streamingAssistantFingerprint = fingerprint

        applyStreamMetadata(to: message, firstTokenTimestamp: now)
        bumpStreamCounters(for: message, delta: piece)
        isLoading = true
        persistSession(reason: .throttled)
        messageContentDidChange.send(.init(messageID: message.id, fingerprint: fingerprint))
    }

    func regenerateSystemMessage(_ message: ChatMessage) {
        guard !sending else { return }
        chatService.cancelStreaming()
        finalizeActiveAssistantMessage(reason: "regenerate", finishedAt: Date())
        currentAssistantMessageID = nil
        interruptedAssistantMessageID = nil
        pendingDeltaWriteBytes = 0

        guard !message.isUser else { return }
        trimMessages(startingAt: message, includeBoundary: true)
        persistSession(reason: .immediate)

        let currentMessages = chronologicalMessages()
        isPriming = true
        isLoading = true
        sending = true
        recordStreamStart(using: currentMessages)
        chatService.fetchStreamedData(messages: currentMessages)
    }

    func retry(afterErrorMessage errorMessage: ChatMessage) {
        guard !sending else { return }
        chatService.cancelStreaming()
        finalizeActiveAssistantMessage(reason: "retry", finishedAt: Date())
        currentAssistantMessageID = nil
        pendingDeltaWriteBytes = 0

        let ordered = chronologicalMessages()
        guard let errorIndex = ordered.firstIndex(where: { $0.id == errorMessage.id }) else { return }
        let priorMessages = ordered.prefix(errorIndex)
        if let precedingUser = priorMessages.last(where: { $0.isUser }) {
            trimMessages(startingAt: precedingUser, includeBoundary: false)
        } else {
            trimMessages(startingAt: errorMessage, includeBoundary: true)
        }

        interruptedAssistantMessageID = nil
        persistSession(reason: .immediate)

        let currentMessages = chronologicalMessages()
        isPriming = true
        isLoading = true
        sending = true
        persistSession(reason: .immediate)

        recordStreamStart(using: currentMessages)
        chatService.fetchStreamedData(messages: currentMessages)
    }

    // MARK: - Editing

    func beginEditUserMessage(_ message: ChatMessage) {
        guard message.isUser else { return }
        editingBaseMessageID = message.id
        userMessage = message.content
    }

    func cancelEditing() {
        editingBaseMessageID = nil
        userMessage = ""
    }

    // MARK: - Session Management
    func attach(session newSession: ChatSession) {
        guard chatSession.id == newSession.id else { return }
        if chatSession !== newSession {
            chatSession = newSession
            orderedMessagesCache = []
            orderedMessagesCacheCount = -1
        }
    }

    // MARK: - Auto Read Helper

    private func bodyTextForAutoRead(from full: String) -> String {
        let parts = full.extractThinkParts()
        let body = parts.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            return body
        }
        // If the model exposed a think section but no body yet, avoid reading anything aloud.
        if parts.think != nil {
            return ""
        }
        return full.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func isPlaceholderTitle(_ title: String) -> Bool {
    let locales = [
        Locale.current.identifier,
        "en",
        "zh-Hans",
        "zh-Hant",
        "ja"
    ]

    for identifier in locales {
        let locale = Locale(identifier: identifier)
        let localizedDefault = String(
            localized: "New Chat",
            locale: locale
        )
        if title == localizedDefault {
            return true
        }
    }
    return false
}
