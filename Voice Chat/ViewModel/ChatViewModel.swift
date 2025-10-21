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

    var onUpdate: (() -> Void)?

    private var sending = false

    private var currentAssistantMessageID: UUID?
    private var interruptedAssistantMessageID: UUID?

    // Toggle to enable realtime text-to-speech for the next assistant response.
    private var enableRealtimeTTSNext: Bool = false
    // Indicates whether the current response is streaming through realtime TTS.
    private var realtimeTTSActive: Bool = false
    // Segment incoming text while skipping <think> blocks.
    private var incSegmenter = IncrementalTextSegmenter()

    // MARK: - Init
    init(chatSession: ChatSession) {
        self.chatSession = chatSession

        // Ensure deltas update on the main actor.
        chatService.onDelta = { [weak self] piece in
            guard let self = self else { return }
            self.handleAssistantDelta(piece)

            // Stream newly segmented text directly to the audio manager when realtime TTS is active.
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

            // Finish realtime playback when an error occurs.
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

            // Flush any remaining realtime segments when the stream ends, otherwise fall back to auto-read.
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

    // MARK: - Realtime speech preparation
    func prepareRealtimeTTSForNextAssistant() {
        enableRealtimeTTSNext = true
    }

    // MARK: - Helpers (stable ordering & safe trimming)

    private func chronologicalMessages() -> [ChatMessage] {
        chatSession.messages.sorted { $0.createdAt < $1.createdAt }
    }

    private func trimMessages(from cutoff: Date, inclusive: Bool) {
        if inclusive {
            chatSession.messages.removeAll { $0.createdAt >= cutoff }
        } else {
            chatSession.messages.removeAll { $0.createdAt > cutoff }
        }
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
            trimMessages(from: base.createdAt, inclusive: true)
            editingBaseMessageID = nil
        }

        let userMsg = ChatMessage(content: trimmedMessage, isUser: true, isActive: true, createdAt: Date(), session: chatSession)
        chatSession.messages.append(userMsg)
        if chatSession.title == "New Chat" {
            chatSession.title = trimmedMessage
        }

        isPriming = true
        isLoading = true
        sending = true
        closeActiveAssistantMessageIfAny()
        interruptedAssistantMessageID = nil
        userMessage = ""
        onUpdate?()

        // Decide whether to enable realtime TTS for this turn.
        realtimeTTSActive = SettingsManager.shared.voiceSettings.enableStreaming && enableRealtimeTTSNext
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
        let cutoff = message.createdAt
        trimMessages(from: cutoff, inclusive: true)
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

        let errorTime = errorMessage.createdAt

        if let idx = chatSession.messages.firstIndex(where: { $0.id == errorMessage.id }) {
            chatSession.messages.remove(at: idx)
        }

        if let interruptedID = interruptedAssistantMessageID,
           let idx2 = chatSession.messages.firstIndex(where: { $0.id == interruptedID }) {
            chatSession.messages.remove(at: idx2)
        } else {
            let candidates = chatSession.messages.enumerated()
                .filter { (_, m) in !m.isUser && m.createdAt <= errorTime && !m.content.hasPrefix("!error:") }
                .sorted(by: { $0.element.createdAt > $1.element.createdAt })
            if let (idx3, _) = candidates.first {
                chatSession.messages.remove(at: idx3)
            }
        }

        if let idxThink = indexOfNearestUnclosedThinkAssistant(beforeOrAt: errorTime) {
            chatSession.messages.remove(at: idxThink)
        }

        interruptedAssistantMessageID = nil

        let currentMessages = chronologicalMessages()
        isPriming = true
        isLoading = true
        sending = true
        onUpdate?()

        chatService.fetchStreamedData(messages: currentMessages)
    }

    // MARK: - Editing flow

    func beginEditUserMessage(_ message: ChatMessage) {
        guard message.isUser else { return }
        editingBaseMessageID = message.id
        userMessage = message.content
    }

    func cancelEditing() {
        editingBaseMessageID = nil
        userMessage = ""
    }

    // MARK: - Retry helpers

    private func indexOfNearestUnclosedThinkAssistant(beforeOrAt time: Date) -> Int? {
        let enumerated = chatSession.messages.enumerated()
            .filter { (_, m) in
                guard !m.isUser, !m.content.hasPrefix("!error:") else { return false }
                return m.createdAt <= time
            }

        for (idx, msg) in enumerated.sorted(by: { $0.element.createdAt > $1.element.createdAt }) {
            if isUnclosedThink(msg.content) { return idx }
        }
        return nil
    }

    private func isUnclosedThink(_ text: String) -> Bool {
        guard let start = text.range(of: "<think>") else { return false }
        let after = text[start.upperBound...]
        return after.range(of: "</think>") == nil
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
