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

    private enum PendingBranchRestore {
        case message(parentID: UUID, previousChildID: UUID?)
    }

    private enum MetricValueSource: String {
        case local
        case provider
    }

    // MARK: - Published State
    @Published var userMessage: String = ""
    @Published var pendingImageAttachments: [ChatImageAttachment] = []
    @Published var isLoading: Bool = false
    @Published var isPriming: Bool = false
    @Published private(set) var isRetrying: Bool = false
    @Published private(set) var retryAttempt: Int = 0
    @Published private(set) var retryLastError: String? = nil
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
    private var pendingServerMetadata: ChatResponseMetadata = .empty
    private var pendingDeltaWriteBytes: Int = 0
    private let deltaPersistThreshold: Int = 2048

    // Flag indicating whether the next request should enable realtime narration (set by the voice overlay).
    private var enableRealtimeTTSNext: Bool = false
    // Tracks whether the current assistant response is being streamed in realtime.
    private var realtimeTTSActive: Bool = false
    // Incremental segmenter that ignores `<think>` sections and splits on punctuation.
    private var incSegmenter = IncrementalTextSegmenter()
    // Cached active-branch chain to avoid repeated traversals when rendering long sessions.
    private var branchMessagesCache: [ChatMessage] = []
    private var branchMessagesCacheCount: Int = -1
    // Cached message lookup for fast ID -> message mapping.
    private var messageLookupCache: [UUID: ChatMessage] = [:]
    private var messageLookupCacheCount: Int = -1
    private var streamingAssistantMessageID: UUID?
    private var streamingAssistantFingerprint: ContentFingerprint?
    private var pendingAssistantParentMessageID: UUID?
    private var pendingBranchRestore: PendingBranchRestore?
    private var autoRetryTask: Task<Void, Never>?
    private var deferredChatConfiguration: ChatServiceConfiguration?
    private let streamRetryPolicy = NetworkRetryPolicy(
        maxAttempts: 2,
        baseDelay: 0.8,
        maxDelay: 18.0,
        backoffFactor: 1.6,
        jitterRatio: 0.2
    )

    // Emits content fingerprint updates (e.g., streaming deltas) to drive targeted UI refreshes.
    let messageContentDidChange = PassthroughSubject<MessageContentUpdate, Never>()
    let branchDidChange = PassthroughSubject<Void, Never>()
    /// Emits a user-facing error string when the current request fails (used by the realtime voice overlay).
    let requestDidFail = PassthroughSubject<String, Never>()

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
            modelIdentifier: resolvedSettings.chatSettings.selectedModel,
            apiKey: resolvedSettings.chatSettings.apiKey,
            providerHint: resolvedSettings.resolvedChatProvider(for: resolvedSettings.chatSettings.apiURL),
            requestStyleHint: resolvedSettings.resolvedChatRequestStyle(for: resolvedSettings.chatSettings.apiURL)
        )
        self.chatServiceFactory = chatServiceFactory ?? { ChatService(configurationProvider: $0) }
        self.chatService = chatService ?? self.chatServiceFactory(self.chatConfiguration)
        self.reachability = reachability ?? ServerReachabilityMonitor.shared
        self.audioManager = audioManager ?? GlobalAudioManager.shared
        self.sessionPersistence = sessionPersistence

        ensureMessageTreeInitializedIfNeeded()

        bindChatService(self.chatService)
    }

    // MARK: - Public API for the realtime overlay
    func prepareRealtimeTTSForNextAssistant() {
        enableRealtimeTTSNext = true
    }

    var hasPendingImageAttachments: Bool {
        !pendingImageAttachments.isEmpty
    }

    func removePendingImageAttachment(id: UUID) {
        pendingImageAttachments.removeAll { $0.id == id }
    }

    func clearPendingImageAttachments() {
        pendingImageAttachments.removeAll()
    }

    func currentModelSupportsImageInput() -> Bool {
        let selected = settingsManager.chatSettings.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveModel = selected.isEmpty ? chatConfiguration.modelIdentifier : selected
        return settingsManager.supportsImageInput(for: effectiveModel)
    }

    func activeBranchContainsImageInputs(includePending: Bool = true) -> Bool {
        if includePending && !pendingImageAttachments.isEmpty {
            return true
        }
        return activeBranchMessages().contains(where: \.hasImageAttachments)
    }

    func shouldWarnAboutUnsupportedImageInputBeforeSending() -> Bool {
        guard !currentModelSupportsImageInput() else { return false }
        let hasDraft = !userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImageAttachments.isEmpty
        guard hasDraft else { return false }
        return activeBranchContainsImageInputs(includePending: true)
    }

    // MARK: - Developer prompt

    private func resolvedDeveloperPrompt(isVoiceMode: Bool) -> String? {
        let preset = isVoiceMode ? settingsManager.selectedVoiceSystemPromptPreset : settingsManager.selectedNormalSystemPromptPreset
        let raw = isVoiceMode ? preset?.voicePrompt : preset?.normalPrompt
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

        service.onResponseMetadata = { [weak self] metadata in
            guard let self = self else { return }
            self.pendingServerMetadata.merge(metadata)
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

        let errorText = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if shouldAutoRetryAfterError(error) {
            scheduleAutoRetry(after: error, errorText: errorText)
            return
        }

        if !errorText.isEmpty {
            requestDidFail.send(errorText)
        }

        isPriming = false
        isLoading = false
        sending = false
        resetRetryState()

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
        let resolvedTimeToFirstToken: TimeInterval? = {
            if let apiTTF = pendingServerMetadata.timeToFirstTokenSeconds,
               apiTTF.isFinite,
               apiTTF >= 0 {
                return apiTTF
            }
            return firstTokenLatency
        }()
        let resolvedTimeToFirstTokenSource: String? =
            pendingServerMetadata.timeToFirstTokenSeconds != nil
            ? MetricValueSource.provider.rawValue
            : (resolvedTimeToFirstToken != nil ? MetricValueSource.local.rawValue : nil)

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

        let resolvedTokenCount: Int = max(0, pendingServerMetadata.outputTokenCount ?? 0)
        let resolvedTokenCountSource: String? =
            pendingServerMetadata.outputTokenCount != nil
            ? MetricValueSource.provider.rawValue
            : (resolvedTokenCount > 0 ? MetricValueSource.local.rawValue : nil)

        let errContent = "!error:\(errorText.isEmpty ? error.localizedDescription : errorText)"
        let err = ChatMessage(
            content: errContent,
            isUser: false,
            isActive: false,
            createdAt: now,
            modelIdentifier: telemetry?.modelIdentifier ?? chatConfiguration.modelIdentifier,
            apiBaseURL: telemetry?.apiBaseURL ?? chatConfiguration.apiBaseURL,
            requestID: telemetry?.streamID,
            providerResponseID: pendingServerMetadata.providerResponseID,
            streamStartedAt: telemetry?.startedAt,
            streamFirstTokenAt: telemetry?.firstTokenAt,
            streamCompletedAt: now,
            timeToFirstToken: resolvedTimeToFirstToken,
            streamDuration: streamDuration,
            generationDuration: generationDuration,
            reasoningOutputTokenCount: pendingServerMetadata.reasoningOutputTokenCount,
            tokensPerSecond: pendingServerMetadata.tokensPerSecond,
            deltaCount: resolvedTokenCount,
            tokenCountSource: resolvedTokenCountSource,
            timeToFirstTokenSource: resolvedTimeToFirstTokenSource,
            tokensPerSecondSource: pendingServerMetadata.tokensPerSecond != nil ? MetricValueSource.provider.rawValue : nil,
            finishReasonSource: pendingServerMetadata.finishReason != nil ? MetricValueSource.provider.rawValue : MetricValueSource.local.rawValue,
            characterCount: errContent.count,
            promptMessageCount: telemetry?.promptMessageCount,
            promptCharacterCount: telemetry?.promptCharacterCount,
            finishReason: pendingServerMetadata.finishReason ?? "error",
            errorDescription: errorText.isEmpty ? error.localizedDescription : errorText,
            session: chatSession
        )
        if err.tokensPerSecond == nil,
           err.tokensPerSecondSource != MetricValueSource.provider.rawValue,
           err.tokenCount > 0,
           let generationDuration = err.generationDuration,
           generationDuration > 0 {
            err.tokensPerSecond = Double(err.tokenCount) / generationDuration
            err.tokensPerSecondSource = MetricValueSource.local.rawValue
        } else if err.tokensPerSecond != nil && err.tokensPerSecondSource == nil {
            err.tokensPerSecondSource = MetricValueSource.provider.rawValue
        }
        if let interrupted {
            err.parentMessage = interrupted
            interrupted.activeChildMessageID = err.id
        } else if let parentID = pendingAssistantParentMessageID,
                  let parent = messageLookup()[parentID] {
            err.parentMessage = parent
            parent.activeChildMessageID = err.id
        }
        chatSession.messages.append(err)
        markSessionMessageActivity(at: err.createdAt)
        invalidateCachesAfterMessageMutation()
        pendingAssistantParentMessageID = nil
        pendingBranchRestore = nil
        branchDidChange.send(())
        persistSession(reason: .immediate)
        pendingServerMetadata = .empty

        if realtimeTTSActive {
            audioManager.finishRealtimeStream()
            realtimeTTSActive = false
        }

        applyDeferredChatConfigurationIfNeeded()
    }

    private func handleChatStreamFinished() {
        let finishedAt = Date()
        let completedMessage = finalizeActiveAssistantMessage(reason: "completed", finishedAt: finishedAt)
        var candidateFullText: String? = completedMessage?.content
        pendingDeltaWriteBytes = 0

        isPriming = false
        isLoading = false
        sending = false
        resetRetryState()

        if candidateFullText == nil {
            let lastAssistant = chatSession.messages
                .filter { !$0.isUser && !$0.content.hasPrefix("!error:") }
                .sorted(by: { $0.createdAt < $1.createdAt })
                .last
            candidateFullText = lastAssistant?.content
        }

        currentAssistantMessageID = nil
        interruptedAssistantMessageID = nil
        pendingAssistantParentMessageID = nil
        pendingBranchRestore = nil

        persistSession(reason: .immediate)

        if realtimeTTSActive {
            let tails = incSegmenter.finalize()
            for seg in tails where !seg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                audioManager.appendRealtimeSegment(seg)
            }
            audioManager.finishRealtimeStream()
            realtimeTTSActive = false
        }

        applyDeferredChatConfigurationIfNeeded()
    }

    /// Rebuilds the chat streaming service when the API base URL or model changes.
    func updateChatConfiguration(_ configuration: ChatServiceConfiguration) {
        guard configuration != chatConfiguration else {
            // If hints reverted to the currently active service config, drop any stale deferred update.
            deferredChatConfiguration = nil
            return
        }
        if requiresHardChatServiceReset(from: chatConfiguration, to: configuration) {
            applyChatConfiguration(configuration, interruptActiveRequest: true)
            return
        }

        if sending || isLoading || isPriming {
            // Provider/style hints can refresh asynchronously; avoid interrupting an active stream.
            deferredChatConfiguration = configuration
            return
        }

        applyChatConfiguration(configuration, interruptActiveRequest: false)
    }

    private func syncChatConfigurationFromSettingsIfNeeded() {
        let settings = settingsManager.chatSettings
        let latest = ChatServiceConfiguration(
            apiBaseURL: settings.apiURL,
            modelIdentifier: settings.selectedModel,
            apiKey: settings.apiKey,
            providerHint: settingsManager.resolvedChatProvider(for: settings.apiURL),
            requestStyleHint: settingsManager.resolvedChatRequestStyle(for: settings.apiURL)
        )
        updateChatConfiguration(latest)
    }

    private func requiresHardChatServiceReset(from current: ChatServiceConfiguration, to next: ChatServiceConfiguration) -> Bool {
        current.apiBaseURL != next.apiBaseURL
        || current.modelIdentifier != next.modelIdentifier
        || current.apiKey != next.apiKey
    }

    private func applyChatConfiguration(_ configuration: ChatServiceConfiguration, interruptActiveRequest: Bool) {
        if interruptActiveRequest {
            cancelAutoRetryTask()
            chatService.cancelStreaming()
            finalizeActiveAssistantMessage(reason: "config-changed", finishedAt: Date())
            currentAssistantMessageID = nil
            resetRetryState()

            if realtimeTTSActive {
                audioManager.finishRealtimeStream()
                realtimeTTSActive = false
            }

            if isPriming { isPriming = false }
            if isLoading { isLoading = false }
            if sending { sending = false }
            interruptedAssistantMessageID = nil
            pendingAssistantParentMessageID = nil
            pendingBranchRestore = nil
            incSegmenter.reset()
        }

        deferredChatConfiguration = nil
        chatConfiguration = configuration
        let newService = chatServiceFactory(configuration)
        bindChatService(newService)
        pendingDeltaWriteBytes = 0
        objectWillChange.send()
        persistSession(reason: .immediate)
    }

    private func applyDeferredChatConfigurationIfNeeded() {
        guard !sending, !isLoading, !isPriming else { return }
        guard let deferred = deferredChatConfiguration else { return }
        guard deferred != chatConfiguration else {
            deferredChatConfiguration = nil
            return
        }
        applyChatConfiguration(deferred, interruptActiveRequest: false)
    }

    /// Applies hint-only deferred configuration during retry windows where no stream is active.
    private func applyDeferredChatConfigurationForRetryIfNeeded() {
        guard let deferred = deferredChatConfiguration else { return }
        guard deferred != chatConfiguration else {
            deferredChatConfiguration = nil
            return
        }
        guard !requiresHardChatServiceReset(from: chatConfiguration, to: deferred) else { return }
        applyChatConfiguration(deferred, interruptActiveRequest: false)
    }

    // MARK: - Helpers (stable ordering & safe trimming)

    private func persistSession(reason: SessionPersistReason = .throttled) {
        sessionPersistence?.ensureSessionTracked(chatSession)
        sessionPersistence?.persist(session: chatSession, reason: reason)
    }

    private func markSessionMessageActivity(at date: Date) {
        chatSession.registerMessageActivity(at: date)
    }

    private func invalidateBranchMessagesCache() {
        branchMessagesCache = []
        branchMessagesCacheCount = -1
    }

    private func invalidateMessageLookupCache() {
        messageLookupCache = [:]
        messageLookupCacheCount = -1
    }

    private func invalidateCachesAfterMessageMutation() {
        invalidateBranchMessagesCache()
        invalidateMessageLookupCache()
    }

    // MARK: - Telemetry

    private func recordStreamStart(using messages: [ChatMessage]) {
        let eligibleMessages = messages.filter { !$0.content.hasPrefix("!error:") }
        let promptCharacterCount = eligibleMessages.reduce(into: 0) { partial, msg in
            partial += msg.content.count
        }
        pendingDeltaWriteBytes = 0
        pendingServerMetadata = .empty

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
            if message.timeToFirstTokenSource == nil {
                message.timeToFirstTokenSource = MetricValueSource.local.rawValue
            }
        }
    }

    private func estimatedTokenCountFromCharacters(_ characterCount: Int) -> Int {
        guard characterCount > 0 else { return 0 }
        return Int((Double(characterCount) / 4.0).rounded(.up))
    }

    private func bumpStreamCounters(for message: ChatMessage, delta: String) {
        message.characterCount += delta.count
        if message.tokenCountSource != MetricValueSource.provider.rawValue {
            message.tokenCount = estimatedTokenCountFromCharacters(message.characterCount)
            if message.tokenCount > 0 {
                message.tokenCountSource = MetricValueSource.local.rawValue
            }
        }
        maybePersistStreamDelta(delta.count)
    }

    private func maybePersistStreamDelta(_ addedChars: Int) {
        pendingDeltaWriteBytes += addedChars
        guard pendingDeltaWriteBytes >= deltaPersistThreshold else { return }
        pendingDeltaWriteBytes = 0
        persistSession(reason: .immediate)
    }

    private func applyServerMetadata(to message: ChatMessage) {
        let metadata = pendingServerMetadata
        if let responseID = metadata.providerResponseID,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message.providerResponseID = responseID
        }
        if let outputTokenCount = metadata.outputTokenCount {
            message.tokenCount = max(0, outputTokenCount)
            message.tokenCountSource = MetricValueSource.provider.rawValue
        }
        if let reasoningOutputTokenCount = metadata.reasoningOutputTokenCount {
            message.reasoningOutputTokenCount = reasoningOutputTokenCount
        }
        if let finishReason = metadata.finishReason,
           !finishReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message.finishReason = finishReason
            message.finishReasonSource = MetricValueSource.provider.rawValue
        } else if message.finishReason != nil, message.finishReasonSource == nil {
            message.finishReasonSource = MetricValueSource.local.rawValue
        }

        if let apiTTF = metadata.timeToFirstTokenSeconds,
           apiTTF.isFinite,
           apiTTF >= 0 {
            message.timeToFirstToken = apiTTF
            message.timeToFirstTokenSource = MetricValueSource.provider.rawValue
            if let start = message.streamStartedAt {
                message.streamFirstTokenAt = start.addingTimeInterval(apiTTF)
            }
        } else if message.timeToFirstToken != nil, message.timeToFirstTokenSource == nil {
            message.timeToFirstTokenSource = MetricValueSource.local.rawValue
        }

        if let apiTPS = metadata.tokensPerSecond,
           apiTPS.isFinite,
           apiTPS >= 0 {
            message.tokensPerSecond = apiTPS
            message.tokensPerSecondSource = MetricValueSource.provider.rawValue
        } else if let outputTokens = (message.tokenCount > 0 ? message.tokenCount : nil),
                  let generationDuration = message.generationDuration,
                  generationDuration > 0 {
            message.tokensPerSecond = Double(outputTokens) / generationDuration
            message.tokensPerSecondSource = MetricValueSource.local.rawValue
        }

        if message.tokenCountSource == nil, message.tokenCount > 0 {
            message.tokenCountSource = MetricValueSource.local.rawValue
        }
    }

    @discardableResult
    private func finalizeActiveAssistantMessage(reason: String, finishedAt: Date = Date(), errorDescription: String? = nil) -> ChatMessage? {
        guard let id = currentAssistantMessageID ?? interruptedAssistantMessageID,
              let message = chatSession.messages.first(where: { $0.id == id }) else {
            activeStreamTelemetry = nil
            pendingServerMetadata = .empty
            return nil
        }

        message.isActive = false
        if message.finishReason == nil {
            message.finishReason = reason
            if message.finishReasonSource == nil {
                message.finishReasonSource = MetricValueSource.local.rawValue
            }
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
        if message.characterCount == 0 {
            message.characterCount = message.content.count
        }
        if message.tokenCountSource != MetricValueSource.provider.rawValue,
           message.tokenCount == 0,
           message.characterCount > 0 {
            message.tokenCount = estimatedTokenCountFromCharacters(message.characterCount)
            if message.tokenCount > 0 {
                message.tokenCountSource = MetricValueSource.local.rawValue
            }
        }
        applyServerMetadata(to: message)

        activeStreamTelemetry = nil
        pendingServerMetadata = .empty
        if streamingAssistantMessageID == message.id {
            streamingAssistantMessageID = nil
            streamingAssistantFingerprint = nil
        }
        return message
    }

    private func messageLookup() -> [UUID: ChatMessage] {
        let count = chatSession.messages.count
        if count == messageLookupCacheCount && !messageLookupCache.isEmpty {
            return messageLookupCache
        }

        var lookup: [UUID: ChatMessage] = [:]
        lookup.reserveCapacity(count)
        for message in chatSession.messages {
            lookup[message.id] = message
        }

        messageLookupCache = lookup
        messageLookupCacheCount = count
        return lookup
    }

    private func stableMessageOrder(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func rootCandidatesSorted() -> [ChatMessage] {
        chatSession.messages
            .filter { $0.parentMessage == nil }
            .sorted(by: stableMessageOrder)
    }

    private func activeRootMessage() -> ChatMessage? {
        let lookup = messageLookup()
        if let id = chatSession.activeRootMessageID,
           let root = lookup[id] {
            return root
        }

        if let fallback = rootCandidatesSorted().first {
            chatSession.activeRootMessageID = fallback.id
            persistSession(reason: .immediate)
            return fallback
        }

        // Data corruption fallback: break any cycles by promoting the oldest message to a root.
        guard let fallback = chatSession.messages.sorted(by: stableMessageOrder).first else { return nil }
        if fallback.parentMessage != nil {
            fallback.parentMessage = nil
        }
        chatSession.activeRootMessageID = fallback.id
        invalidateBranchMessagesCache()
        persistSession(reason: .immediate)
        return fallback
    }

    private func activeBranchMessages() -> [ChatMessage] {
        let count = chatSession.messages.count
        if count == branchMessagesCacheCount && !branchMessagesCache.isEmpty {
            return branchMessagesCache
        }

        guard let root = activeRootMessage() else { return [] }
        let lookup = messageLookup()

        var out: [ChatMessage] = []
        out.reserveCapacity(min(64, count))

        var visited = Set<UUID>()
        var current: ChatMessage? = root
        while let message = current, visited.insert(message.id).inserted {
            out.append(message)
            guard let nextID = message.activeChildMessageID,
                  let next = lookup[nextID] else {
                break
            }
            current = next
        }

        branchMessagesCache = out
        branchMessagesCacheCount = count
        return out
    }

    /// Exposes the cached active branch chain for UI rendering.
    func orderedMessagesCached() -> [ChatMessage] {
        activeBranchMessages()
    }

    private func ensureMessageTreeInitializedIfNeeded() {
        guard !chatSession.messages.isEmpty else { return }
        guard !sending else { return }

        var didMutate = false
        var didMutateBranch = false

        // Ensure all messages are associated with the current session.
        for message in chatSession.messages {
            if message.session?.id != chatSession.id {
                message.session = chatSession
                didMutate = true
            }
        }

        let messages = chatSession.messages
        var lookup: [UUID: ChatMessage] = [:]
        lookup.reserveCapacity(messages.count)
        for message in messages {
            lookup[message.id] = message
        }

        // Drop parent pointers that point outside this session (or to self).
        for message in messages {
            if let parent = message.parentMessage {
                if parent.id == message.id || lookup[parent.id] == nil {
                    message.parentMessage = nil
                    didMutate = true
                    didMutateBranch = true
                }
            }
        }

        // Break any parent cycles so we always have at least one root.
        for message in messages {
            var visited = Set<UUID>()
            var current: ChatMessage? = message
            while let cur = current {
                if !visited.insert(cur.id).inserted {
                    if cur.parentMessage != nil {
                        cur.parentMessage = nil
                        didMutate = true
                        didMutateBranch = true
                    }
                    break
                }

                guard let parent = cur.parentMessage else { break }
                if lookup[parent.id] == nil {
                    cur.parentMessage = nil
                    didMutate = true
                    didMutateBranch = true
                    break
                }
                current = parent
            }
        }

        // Ensure we always have a valid root selection.
        var roots = messages.filter { $0.parentMessage == nil }.sorted(by: stableMessageOrder)
        if roots.isEmpty, let fallback = messages.sorted(by: stableMessageOrder).first {
            fallback.parentMessage = nil
            roots = [fallback]
            didMutate = true
            didMutateBranch = true
        }

        if let activeID = chatSession.activeRootMessageID,
           let active = lookup[activeID] {
            if active.parentMessage != nil {
                var visited = Set<UUID>()
                var cursor = active
                while let parent = cursor.parentMessage,
                      visited.insert(cursor.id).inserted {
                    cursor = parent
                }
                if chatSession.activeRootMessageID != cursor.id {
                    chatSession.activeRootMessageID = cursor.id
                    didMutate = true
                    didMutateBranch = true
                }
            }
        } else if let fallback = roots.first {
            chatSession.activeRootMessageID = fallback.id
            didMutate = true
            didMutateBranch = true
        }

        // Ensure activeChildMessageID always points at an actual child if children exist.
        var childrenByParent: [UUID: [ChatMessage]] = [:]
        childrenByParent.reserveCapacity(messages.count)
        for message in messages {
            if let parent = message.parentMessage {
                childrenByParent[parent.id, default: []].append(message)
            }
        }

        for parent in messages {
            let children = childrenByParent[parent.id, default: []].sorted(by: stableMessageOrder)
            guard !children.isEmpty else {
                if parent.activeChildMessageID != nil {
                    parent.activeChildMessageID = nil
                    didMutate = true
                    didMutateBranch = true
                }
                continue
            }

            if let activeChildID = parent.activeChildMessageID,
               children.contains(where: { $0.id == activeChildID }) {
                continue
            }

            if let fallback = children.last, parent.activeChildMessageID != fallback.id {
                parent.activeChildMessageID = fallback.id
                didMutate = true
                didMutateBranch = true
            }
        }

        // If the app was terminated mid-stream, assistant messages may have been persisted as active.
        if finalizeDanglingActiveAssistantMessagesIfNeeded() {
            didMutate = true
        }

        guard didMutate else { return }

        // Only refresh branch rendering if the branch structure changed.
        if didMutateBranch {
            invalidateBranchMessagesCache()
            branchDidChange.send(())
        }
        invalidateMessageLookupCache()
        persistSession(reason: .immediate)
    }

    @discardableResult
    private func finalizeDanglingActiveAssistantMessagesIfNeeded(now: Date = Date()) -> Bool {
        guard !sending else { return false }
        var didChange = false

        for message in chatSession.messages where !message.isUser && message.isActive {
            message.isActive = false
            if message.finishReason == nil {
                message.finishReason = "interrupted"
                if message.finishReasonSource == nil {
                    message.finishReasonSource = MetricValueSource.local.rawValue
                }
            }
            if message.streamStartedAt == nil {
                message.streamStartedAt = message.createdAt
            }
            if message.streamCompletedAt == nil {
                message.streamCompletedAt = now
            }
            if let start = message.streamStartedAt, message.streamDuration == nil {
                message.streamDuration = now.timeIntervalSince(start)
            }
            if let first = message.streamFirstTokenAt, message.generationDuration == nil {
                message.generationDuration = now.timeIntervalSince(first)
            }
            if message.characterCount == 0 {
                message.characterCount = message.content.count
            }
            if message.tokenCountSource != MetricValueSource.provider.rawValue,
               message.tokenCount == 0,
               message.characterCount > 0 {
                message.tokenCount = estimatedTokenCountFromCharacters(message.characterCount)
                if message.tokenCount > 0 {
                    message.tokenCountSource = MetricValueSource.local.rawValue
                }
            }
            if message.timeToFirstToken != nil && message.timeToFirstTokenSource == nil {
                message.timeToFirstTokenSource = MetricValueSource.local.rawValue
            }
            if message.tokensPerSecond == nil,
               message.tokenCount > 0,
               let generationDuration = message.generationDuration,
               generationDuration > 0 {
                message.tokensPerSecond = Double(message.tokenCount) / generationDuration
                message.tokensPerSecondSource = MetricValueSource.local.rawValue
            }
            didChange = true
        }

        if didChange {
            isPriming = false
            isLoading = false
            sending = false
        }
        return didChange
    }

    // MARK: - Intent

    @discardableResult
    func sendMessage(ignoringUnsupportedImageInputs: Bool = false) -> Bool {
        syncChatConfigurationFromSettingsIfNeeded()
        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftAttachments = pendingImageAttachments
        guard !trimmedMessage.isEmpty || !draftAttachments.isEmpty else { return false }
        guard !sending else { return false }

        let supportsImageInputs = currentModelSupportsImageInput()
        let hasImageContext = activeBranchContainsImageInputs(includePending: true)
        if hasImageContext && !supportsImageInputs && !ignoringUnsupportedImageInputs {
            return false
        }

        let attachmentsForMessage = supportsImageInputs ? draftAttachments : []
        guard !trimmedMessage.isEmpty || !attachmentsForMessage.isEmpty else {
            return false
        }

        resetRetryState()
        ensureMessageTreeInitializedIfNeeded()

        let parentMessage: ChatMessage?
        if let baseID = editingBaseMessageID,
           let base = chatSession.messages.first(where: { $0.id == baseID }) {
            parentMessage = base.parentMessage
            editingBaseMessageID = nil
        } else {
            parentMessage = activeBranchMessages().last
        }

        let now = Date()
        let userMsg = ChatMessage(
            content: trimmedMessage,
            imageAttachments: attachmentsForMessage,
            isUser: true,
            isActive: true,
            createdAt: now,
            deltaCount: estimatedTokenCountFromCharacters(trimmedMessage.count),
            tokenCountSource: MetricValueSource.local.rawValue,
            characterCount: trimmedMessage.count,
            session: chatSession
        )
        userMsg.parentMessage = parentMessage
        if let parentMessage {
            parentMessage.activeChildMessageID = userMsg.id
        } else {
            chatSession.activeRootMessageID = userMsg.id
        }
        chatSession.messages.append(userMsg)
        markSessionMessageActivity(at: userMsg.createdAt)
        invalidateCachesAfterMessageMutation()
        branchDidChange.send(())
        pendingBranchRestore = nil
        if isPlaceholderTitle(chatSession.title), !trimmedMessage.isEmpty {
            chatSession.title = trimmedMessage
        }
        persistSession(reason: .immediate)

        isPriming = true
        isLoading = true
        sending = true
        finalizeActiveAssistantMessage(reason: "superseded", finishedAt: Date())
        interruptedAssistantMessageID = nil
        currentAssistantMessageID = nil
        pendingAssistantParentMessageID = userMsg.id
        pendingDeltaWriteBytes = 0
        userMessage = ""
        pendingImageAttachments.removeAll()
        persistSession(reason: .immediate)

        // Determine whether this response should use realtime narration.
        realtimeTTSActive = enableRealtimeTTSNext
        enableRealtimeTTSNext = false
        if realtimeTTSActive {
            incSegmenter.reset()
            audioManager.startRealtimeStream()
        }

        let currentMessages = activeBranchMessages()
        recordStreamStart(using: currentMessages)
        let developerPrompt = resolvedDeveloperPrompt(isVoiceMode: realtimeTTSActive || audioManager.isRealtimeMode)
        chatService.fetchStreamedData(
            messages: currentMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: supportsImageInputs
        )
        return true
    }

    func cancelCurrentRequest() {
        guard sending || isLoading || isPriming else { return }
        let finishedAt = Date()
        cancelAutoRetryTask()
        chatService.cancelStreaming()
        finalizeActiveAssistantMessage(reason: "cancelled", finishedAt: finishedAt)

        if currentAssistantMessageID == nil,
           let restore = pendingBranchRestore {
            if case let .message(parentID, previousChildID) = restore,
               let parent = messageLookup()[parentID] {
                parent.activeChildMessageID = previousChildID
            }
            invalidateBranchMessagesCache()
            branchDidChange.send(())
        }

        currentAssistantMessageID = nil
        interruptedAssistantMessageID = nil
        pendingAssistantParentMessageID = nil
        pendingBranchRestore = nil
        pendingDeltaWriteBytes = 0
        isPriming = false
        isLoading = false
        sending = false
        resetRetryState()
        persistSession(reason: .immediate)

        if realtimeTTSActive {
            audioManager.finishRealtimeStream()
            realtimeTTSActive = false
        }

        applyDeferredChatConfigurationIfNeeded()
    }

    private func handleAssistantDelta(_ piece: String) {
        guard isPriming || isLoading || sending else { return }
        markRetryProgressIfNeeded()

        if isPriming { isPriming = false }
        let now = Date()

        let message: ChatMessage
        let fingerprint: ContentFingerprint
        let didCreateAssistantMessage: Bool
        if let id = currentAssistantMessageID,
           let existing = messageLookup()[id] {
            let previousFingerprint = (streamingAssistantMessageID == existing.id) ? streamingAssistantFingerprint : nil
            existing.content += piece
            // Streaming deltas count as chat activity for sidebar ordering/grouping.
            markSessionMessageActivity(at: now)
            message = existing
            didCreateAssistantMessage = false
            if let previousFingerprint {
                fingerprint = previousFingerprint.appending(piece)
            } else {
                fingerprint = ContentFingerprint.make(existing.content)
            }
        } else {
            let sys = ChatMessage(content: piece, isUser: false, isActive: true, createdAt: now, session: chatSession)
            let parent: ChatMessage?
            if let parentID = pendingAssistantParentMessageID,
               let resolved = messageLookup()[parentID] {
                parent = resolved
                pendingAssistantParentMessageID = nil
            } else {
                parent = activeBranchMessages().last
            }
            if let parent {
                sys.parentMessage = parent
                parent.activeChildMessageID = sys.id
            } else {
                chatSession.activeRootMessageID = sys.id
            }
            chatSession.messages.append(sys)
            markSessionMessageActivity(at: sys.createdAt)
            invalidateCachesAfterMessageMutation()
            pendingBranchRestore = nil
            branchDidChange.send(())
            currentAssistantMessageID = sys.id
            message = sys
            didCreateAssistantMessage = true
            fingerprint = ContentFingerprint.make(piece)
        }
        streamingAssistantMessageID = message.id
        streamingAssistantFingerprint = fingerprint

        applyStreamMetadata(to: message, firstTokenTimestamp: now)
        bumpStreamCounters(for: message, delta: piece)
        isLoading = true
        if didCreateAssistantMessage {
            persistSession(reason: .immediate)
        }
        messageContentDidChange.send(.init(messageID: message.id, fingerprint: fingerprint))
    }

    func regenerateSystemMessage(_ message: ChatMessage) {
        guard !sending else { return }
        syncChatConfigurationFromSettingsIfNeeded()
        ensureMessageTreeInitializedIfNeeded()
        resetRetryState()
        chatService.cancelStreaming()
        finalizeActiveAssistantMessage(reason: "regenerate", finishedAt: Date())
        currentAssistantMessageID = nil
        interruptedAssistantMessageID = nil
        pendingAssistantParentMessageID = nil
        pendingDeltaWriteBytes = 0

        guard !message.isUser else { return }
        guard let parent = message.parentMessage else { return }

        persistSession(reason: .immediate)

        pendingBranchRestore = .message(parentID: parent.id, previousChildID: parent.activeChildMessageID)
        parent.activeChildMessageID = nil
        invalidateBranchMessagesCache()
        branchDidChange.send(())

        pendingAssistantParentMessageID = parent.id
        let currentMessages = activeBranchMessages()
        isPriming = true
        isLoading = true
        sending = true
        recordStreamStart(using: currentMessages)
        let developerPrompt = resolvedDeveloperPrompt(isVoiceMode: audioManager.isRealtimeMode)
        chatService.fetchStreamedData(
            messages: currentMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: currentModelSupportsImageInput()
        )
    }

    func retry(afterErrorMessage errorMessage: ChatMessage) {
        guard !sending else { return }
        syncChatConfigurationFromSettingsIfNeeded()
        ensureMessageTreeInitializedIfNeeded()
        resetRetryState()
        chatService.cancelStreaming()
        finalizeActiveAssistantMessage(reason: "retry", finishedAt: Date())
        currentAssistantMessageID = nil
        interruptedAssistantMessageID = nil
        pendingAssistantParentMessageID = nil
        pendingDeltaWriteBytes = 0

        let active = activeBranchMessages()
        guard let errorIndex = active.firstIndex(where: { $0.id == errorMessage.id }) else { return }
        let priorMessages = active.prefix(errorIndex)
        guard let precedingUser = priorMessages.last(where: { $0.isUser }) else { return }

        persistSession(reason: .immediate)

        pendingBranchRestore = .message(parentID: precedingUser.id, previousChildID: precedingUser.activeChildMessageID)
        precedingUser.activeChildMessageID = nil
        invalidateBranchMessagesCache()
        branchDidChange.send(())

        pendingAssistantParentMessageID = precedingUser.id
        let currentMessages = activeBranchMessages()
        isPriming = true
        isLoading = true
        sending = true

        recordStreamStart(using: currentMessages)
        let developerPrompt = resolvedDeveloperPrompt(isVoiceMode: audioManager.isRealtimeMode)
        chatService.fetchStreamedData(
            messages: currentMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: currentModelSupportsImageInput()
        )
    }

    func switchToMessageVersion(_ message: ChatMessage) {
        guard !sending else { return }
        ensureMessageTreeInitializedIfNeeded()
        if let parent = message.parentMessage {
            parent.activeChildMessageID = message.id
        } else {
            chatSession.activeRootMessageID = message.id
        }
        invalidateBranchMessagesCache()
        branchDidChange.send(())
        persistSession(reason: .immediate)
    }

    // MARK: - Editing

    func beginEditUserMessage(_ message: ChatMessage) {
        guard message.isUser else { return }
        editingBaseMessageID = message.id
        userMessage = message.content
        pendingImageAttachments = message.imageAttachments
    }

    func cancelEditing() {
        editingBaseMessageID = nil
        userMessage = ""
        pendingImageAttachments = []
    }

    // MARK: - Auto Retry (Text Streaming)

    private func shouldAutoRetryAfterError(_ error: Error) -> Bool {
        // Cap retry rounds for a single request episode.
        guard streamRetryPolicy.shouldContinue(afterAttempt: retryAttempt + 1) else { return false }
        if NetworkRetryability.isCancellation(error) { return false }
        if let err = error as? ChatNetworkError {
            switch err {
            case .invalidURL:
                return false
            case .timeout:
                return true
            case .emptyResponse:
                // Empty payloads are usually protocol/format mismatches, not transient network failures.
                return false
            case .serverError(let statusCode, _):
                if let statusCode {
                    return NetworkRetryability.shouldRetry(HTTPStatusError(statusCode: statusCode, bodyPreview: nil))
                }
                return false
            }
        }
        return NetworkRetryability.shouldRetry(error)
    }

    private func scheduleAutoRetry(after error: Error, errorText: String) {
        cancelAutoRetryTask()

        // Keep the request "active" so the Stop button remains visible.
        isLoading = true
        sending = true
        if currentAssistantMessageID == nil {
            isPriming = true
        }

        if !isRetrying {
            // New disconnect episode: reset the counter so the UI starts from attempt 1 again.
            retryAttempt = 0
        }
        retryAttempt += 1
        isRetrying = true
        retryLastError = errorText.isEmpty ? error.localizedDescription : errorText

        let retryCount = retryAttempt
        let delay = streamRetryPolicy.delay(forRetryCount: retryCount)
        let shouldUseVoicePrompt = realtimeTTSActive || audioManager.isRealtimeMode

        autoRetryTask = Task { [weak self] in
            await NetworkRetry.sleep(seconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.isLoading || self.isPriming || self.sending else {
                    self.resetRetryState()
                    return
                }
                // Avoid silently switching prompt modes if the user changes modes between retries.
                if !shouldUseVoicePrompt && (self.realtimeTTSActive || self.audioManager.isRealtimeMode) {
                    self.resetRetryState()
                    self.handleChatServiceError(error)
                    return
                }

                self.applyDeferredChatConfigurationForRetryIfNeeded()
                let currentMessages = self.activeBranchMessages()
                let developerPrompt = self.resolvedDeveloperPrompt(isVoiceMode: shouldUseVoicePrompt)
                self.chatService.fetchStreamedData(
                    messages: currentMessages,
                    developerPrompt: developerPrompt,
                    includeImagesInUserContent: self.currentModelSupportsImageInput()
                )
            }
        }
    }

    private func cancelAutoRetryTask() {
        autoRetryTask?.cancel()
        autoRetryTask = nil
    }

    private func markRetryProgressIfNeeded() {
        if isRetrying {
            isRetrying = false
            retryAttempt = 0
            retryLastError = nil
        }
    }

    private func resetRetryState() {
        cancelAutoRetryTask()
        isRetrying = false
        retryAttempt = 0
        retryLastError = nil
    }

    // MARK: - Session Management
    func attach(session newSession: ChatSession) {
        guard chatSession.id == newSession.id else { return }
        if chatSession !== newSession {
            chatSession = newSession
            invalidateCachesAfterMessageMutation()
            ensureMessageTreeInitializedIfNeeded()
        }
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
