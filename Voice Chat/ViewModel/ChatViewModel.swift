//
//  ChatViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/18.
//

import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published State
    @Published var userMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var isPriming: Bool = false
    @Published var chatSession: ChatSession

    @Published var editingBaseMessageID: UUID? = nil
    var isEditing: Bool { editingBaseMessageID != nil }

    // MARK: - Dependencies
    private let chatService = ChatService()
    private let settingsManager = SettingsManager.shared
    private let reachability = ServerReachabilityMonitor.shared

    var onUpdate: (() -> Void)?

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
    init(chatSession: ChatSession) {
        self.chatSession = chatSession
        if chatSession.messages.contains(where: { !$0.isUser && $0.isActive }) {
            self.isLoading = true
        }

        // Deliver streaming deltas back on the main actor.
        chatService.onDelta = { [weak self] piece in
            guard let self = self else { return }
            self.handleAssistantDelta(piece)

            // Realtime narration: send body text segments to the audio manager as they become available.
            if self.realtimeTTSActive {
                let newSegments = self.incSegmenter.append(piece)
                for seg in newSegments where !seg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    GlobalAudioManager.shared.appendRealtimeSegment(seg)
                }
            }
        }
        chatService.onError = { [weak self] error in
            guard let self = self else { return }
            self.isPriming = false
            self.isLoading = false
            self.sending = false

            if let id = self.currentAssistantMessageID,
               let last = self.chatSession.messages.first(where: { $0.id == id }) {
                last.isActive = false
                self.interruptedAssistantMessageID = id
            } else {
                self.interruptedAssistantMessageID = nil
            }
            self.currentAssistantMessageID = nil

            let err = ChatMessage(
                content: "!error:\(error.localizedDescription)",
                isUser: false,
                isActive: false,
                createdAt: Date(),
                session: self.chatSession
            )
            self.chatSession.messages.append(err)
            self.onUpdate?()

            // If an error occurs during realtime playback, finish the stream gracefully.
            if self.realtimeTTSActive {
                GlobalAudioManager.shared.finishRealtimeStream()
                self.realtimeTTSActive = false
            }
        }
        chatService.onStreamFinished = { [weak self] in
            guard let self = self else { return }

            var candidateFullText: String?

            if let id = self.currentAssistantMessageID,
               let last = self.chatSession.messages.first(where: { $0.id == id }) {
                last.isActive = false
                candidateFullText = last.content
            }

            self.isPriming = false
            self.isLoading = false
            self.sending = false

            if candidateFullText == nil {
                let lastAssistant = self.chatSession.messages
                    .filter { !$0.isUser && !$0.content.hasPrefix("!error:") }
                    .sorted(by: { $0.createdAt < $1.createdAt })
                    .last
                candidateFullText = lastAssistant?.content
            }

            self.currentAssistantMessageID = nil
            self.interruptedAssistantMessageID = nil

            self.onUpdate?()

            // When streaming ends, flush any remaining realtime buffer or fall back to auto playback.
            if self.realtimeTTSActive {
                let tails = self.incSegmenter.finalize()
                for seg in tails where !seg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    GlobalAudioManager.shared.appendRealtimeSegment(seg)
                }
                GlobalAudioManager.shared.finishRealtimeStream()
                self.realtimeTTSActive = false
            } else if self.settingsManager.voiceSettings.autoReadAfterGeneration {
                let body = self.bodyTextForAutoRead(from: candidateFullText ?? "")
                if !body.isEmpty {
                    GlobalAudioManager.shared.startProcessing(text: body)
                }
            }
        }
    }

    // MARK: - Public API for the realtime overlay
    func prepareRealtimeTTSForNextAssistant() {
        enableRealtimeTTSNext = true
    }

    // MARK: - Helpers (stable ordering & safe trimming)

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
            onUpdate?()
            return
        }

        isPriming = true
        isLoading = true
        sending = true
        closeActiveAssistantMessageIfAny()
        interruptedAssistantMessageID = nil
        userMessage = ""
        onUpdate?()

        // Determine whether this response should use realtime narration.
        realtimeTTSActive = enableRealtimeTTSNext
        enableRealtimeTTSNext = false
        if realtimeTTSActive {
            incSegmenter.reset()
            GlobalAudioManager.shared.startRealtimeStream()
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
        onUpdate?()

        if realtimeTTSActive {
            GlobalAudioManager.shared.finishRealtimeStream()
            realtimeTTSActive = false
        }
    }

    private func handleAssistantDelta(_ piece: String) {
        guard isPriming || isLoading || sending else { return }

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
        onUpdate?()
    }

    func regenerateSystemMessage(_ message: ChatMessage) {
        guard !sending else { return }
        chatService.cancelStreaming()
        closeActiveAssistantMessageIfAny()
        interruptedAssistantMessageID = nil

        guard !message.isUser else { return }
        trimMessages(startingAt: message, includeBoundary: true)
        onUpdate?()

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

        let currentMessages = chronologicalMessages()
        isPriming = true
        isLoading = true
        sending = true
        onUpdate?()

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
