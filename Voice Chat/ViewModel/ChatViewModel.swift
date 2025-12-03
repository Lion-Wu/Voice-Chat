//
//  ChatViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/18.
//

import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
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

    // Flag indicating whether the next request should enable realtime narration (set by the voice overlay).
    private var enableRealtimeTTSNext: Bool = false
    // Tracks whether the current assistant response is being streamed in realtime.
    private var realtimeTTSActive: Bool = false
    // Incremental segmenter that ignores `<think>` sections and splits on punctuation.
    private var incSegmenter = IncrementalTextSegmenter()

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
        isPriming = false
        isLoading = false
        sending = false

        if let id = currentAssistantMessageID,
           let last = chatSession.messages.first(where: { $0.id == id }) {
            last.isActive = false
            interruptedAssistantMessageID = id
        } else {
            interruptedAssistantMessageID = nil
        }
        currentAssistantMessageID = nil

        let err = ChatMessage(
            content: "!error:\(error.localizedDescription)",
            isUser: false,
            isActive: false,
            createdAt: Date(),
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
        var candidateFullText: String?

        if let id = currentAssistantMessageID,
           let last = chatSession.messages.first(where: { $0.id == id }) {
            last.isActive = false
            candidateFullText = last.content
        }

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
        closeActiveAssistantMessageIfAny()

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
        persistSession(reason: .immediate)
    }

    // MARK: - Helpers (stable ordering & safe trimming)

    private func persistSession(reason: SessionPersistReason = .throttled) {
        sessionPersistence?.ensureSessionTracked(chatSession)
        sessionPersistence?.persist(session: chatSession, reason: reason)
    }

    /// Returns messages sorted by time while preserving insertion order for identical timestamps.
    private func chronologicalMessages() -> [ChatMessage] {
        chatSession.messages
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)
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

    private func closeActiveAssistantMessageIfAny() {
        if let id = currentAssistantMessageID,
           let msg = chatSession.messages.first(where: { $0.id == id }) {
            msg.isActive = false
        }
        currentAssistantMessageID = nil
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

        let userMsg = ChatMessage(content: trimmedMessage, isUser: true, isActive: true, createdAt: Date(), session: chatSession)
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
            closeActiveAssistantMessageIfAny()
            interruptedAssistantMessageID = nil

            let errText = NSLocalizedString("Unable to reach the text server. Please check your connection or server settings.", comment: "Shown when sending a message while the text server is unreachable")
            let err = ChatMessage(
                content: "!error:\(errText)",
                isUser: false,
                isActive: false,
                createdAt: Date(),
                session: chatSession
            )
            chatSession.messages.append(err)
            persistSession(reason: .immediate)
            return
        }

        isPriming = true
        isLoading = true
        sending = true
        closeActiveAssistantMessageIfAny()
        interruptedAssistantMessageID = nil
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
        chatService.fetchStreamedData(messages: currentMessages)
    }

    func cancelCurrentRequest() {
        guard sending || isLoading || isPriming else { return }
        chatService.cancelStreaming()
        closeActiveAssistantMessageIfAny()
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

        if let id = currentAssistantMessageID,
           let msg = chatSession.messages.first(where: { $0.id == id }) {
            msg.content += piece
        } else {
            let sys = ChatMessage(content: piece, isUser: false, isActive: true, createdAt: Date(), session: chatSession)
            chatSession.messages.append(sys)
            currentAssistantMessageID = sys.id
        }

        isLoading = true
        persistSession(reason: .throttled)
    }

    func regenerateSystemMessage(_ message: ChatMessage) {
        guard !sending else { return }
        chatService.cancelStreaming()
        closeActiveAssistantMessageIfAny()
        interruptedAssistantMessageID = nil

        guard !message.isUser else { return }
        trimMessages(startingAt: message, includeBoundary: true)
        persistSession(reason: .immediate)

        let currentMessages = chronologicalMessages()
        isPriming = true
        isLoading = true
        sending = true
        chatService.fetchStreamedData(messages: currentMessages)
    }

    func retry(afterErrorMessage errorMessage: ChatMessage) {
        guard !sending else { return }
        chatService.cancelStreaming()
        closeActiveAssistantMessageIfAny()

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
        }
    }

    // MARK: - Auto Read Helper

    private func bodyTextForAutoRead(from full: String) -> String {
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let start = trimmed.range(of: "<think>") {
            if let end = trimmed.range(of: "</think>", range: start.upperBound..<trimmed.endIndex) {
                let body = trimmed[end.upperBound...]
                return String(body).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return ""
            }
        }
        return trimmed
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
