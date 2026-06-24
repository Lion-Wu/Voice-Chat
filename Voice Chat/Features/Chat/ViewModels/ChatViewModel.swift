//
//  ChatViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/18.
//

import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    struct MessageContentUpdate: Sendable {
        let messageID: UUID
        let fingerprint: ContentFingerprint
    }

    // MARK: - Published State
    @Published var userMessage: String = ""
    @Published var pendingImageAttachments: [ChatImageAttachment] = []
    @Published var queuedDraftCoordinator = ChatQueuedDraftCoordinator()
    @Published var isLoading: Bool = false
    @Published var isPriming: Bool = false
    @Published private(set) var isRetrying: Bool = false
    @Published private(set) var retryAttempt: Int = 0
    @Published private(set) var retryLastError: String? = nil
    @Published private(set) var toolActivities: [ChatToolActivity] = []
    @Published private(set) var messageToolActivities: [UUID: [ChatToolActivity]] = [:]
    @Published private(set) var messageToolActivityPlacements: [UUID: [ChatToolActivityPlacement]] = [:]
    @Published var chatSession: ChatSession

    @Published var editingBaseMessageID: UUID? = nil
    var isEditing: Bool { editingBaseMessageID != nil }
    var isEditingQueuedDraft: Bool { queuedDraftCoordinator.isEditing }
    var isEditingComposerDraft: Bool { isEditing || isEditingQueuedDraft }
    var queuedDrafts: [QueuedChatDraft] { queuedDraftCoordinator.drafts }
    var pendingUnsupportedImageQueuedDraftID: UUID? { queuedDraftCoordinator.pendingUnsupportedImageDraftID }

    // MARK: - Dependencies
    private let textRequestRuntime: ChatTextRequestRuntime
    private var chatConfiguration: ChatServiceConfiguration { textRequestRuntime.configuration }
    private let runtimeConfigurationResolver: ChatRuntimeConfigurationResolver
    private let settingsManager: SettingsManager
    private let reachability: ServerReachabilityMonitor
    private let audioManager: GlobalAudioManager
    private let sessionMutationController: ChatSessionMutationController

    private var sending: Bool { textRequestRuntime.sending }
    var hasActiveTextRequest: Bool { textRequestRuntime.hasActiveTextRequest }
    private var currentAssistantMessageID: UUID? {
        get { textRequestRuntime.currentAssistantMessageID }
        set { textRequestRuntime.currentAssistantMessageID = newValue }
    }
    private var interruptedAssistantMessageID: UUID? {
        get { textRequestRuntime.interruptedAssistantMessageID }
        set { textRequestRuntime.interruptedAssistantMessageID = newValue }
    }
    private var pendingAssistantParentMessageID: UUID? {
        get { textRequestRuntime.pendingAssistantParentMessageID }
        set { textRequestRuntime.pendingAssistantParentMessageID = newValue }
    }

    private let realtimeNarrationCoordinator: ChatRealtimeNarrationCoordinator
    private var streamingAssistantMessageID: UUID? {
        get { textRequestRuntime.streamingAssistantMessageID }
        set { textRequestRuntime.streamingAssistantMessageID = newValue }
    }
    private var streamingAssistantFingerprint: ContentFingerprint? {
        get { textRequestRuntime.streamingAssistantFingerprint }
        set { textRequestRuntime.streamingAssistantFingerprint = newValue }
    }
    private let branchRestartCoordinator = ChatBranchRestartCoordinator()
    let queuedDraftAutostartController = ChatQueuedDraftAutostartController()

    // Emits content fingerprint updates (e.g., streaming deltas) to drive targeted UI refreshes.
    let messageContentDidChange = PassthroughSubject<MessageContentUpdate, Never>()
    let branchDidChange = PassthroughSubject<Void, Never>()
    /// Emits a user-facing error string when the current request fails (used by the realtime voice overlay).
    let requestDidFail = PassthroughSubject<String, Never>()

    // MARK: - Init
    init(
        chatSession: ChatSession,
        settingsManager: SettingsManager,
        reachability: ServerReachabilityMonitor,
        audioManager: GlobalAudioManager,
        chatService: ChatStreamingService? = nil,
        chatServiceFactory: ((ChatServiceConfiguring) -> ChatStreamingService)? = nil,
        sessionPersistence: (any ChatSessionPersisting & ChatSessionActivityPublishing)? = nil
    ) {
        self.chatSession = chatSession
        self.settingsManager = settingsManager
        let resolvedRuntimeConfiguration = ChatRuntimeConfigurationResolver(settingsManager: settingsManager)
        self.runtimeConfigurationResolver = resolvedRuntimeConfiguration
        let initialChatConfiguration = resolvedRuntimeConfiguration.currentConfiguration()
        let resolvedChatServiceFactory = chatServiceFactory ?? { ChatService(configurationProvider: $0) }
        self.textRequestRuntime = ChatTextRequestRuntime(
            configuration: initialChatConfiguration,
            service: chatService,
            serviceFactory: resolvedChatServiceFactory
        )
        self.reachability = reachability
        self.audioManager = audioManager
        self.realtimeNarrationCoordinator = ChatRealtimeNarrationCoordinator(audioManager: audioManager)
        self.sessionMutationController = ChatSessionMutationController(
            sessionPersistence: sessionPersistence,
            branchDidChange: branchDidChange
        )

        bindRequestActivityController()
        bindStreamRetryStatusController()
        ensureMessageTreeInitializedIfNeeded()
        bindStreamingSession()
    }

    // MARK: - Public API for the realtime overlay
    func prepareRealtimeTTSForNextAssistant() {
        realtimeNarrationCoordinator.prepareNextAssistant()
    }

    var hasPendingImageAttachments: Bool { !pendingImageAttachments.isEmpty }

    func removePendingImageAttachment(id: UUID) { pendingImageAttachments.removeAll { $0.id == id } }

    func clearPendingImageAttachments() { pendingImageAttachments.removeAll() }

    func currentModelSupportsImageInput() -> Bool { runtimeConfigurationResolver.supportsImageInput(fallbackModelIdentifier: chatConfiguration.modelIdentifier) }

    func currentModelThinkingCapability() -> ModelThinkingCapability? { runtimeConfigurationResolver.thinkingCapability(fallbackModelIdentifier: chatConfiguration.modelIdentifier) }

    func currentThinkingOption() -> ModelThinkingOption? { runtimeConfigurationResolver.selectedThinkingOption(fallbackModelIdentifier: chatConfiguration.modelIdentifier) }

    func setCurrentThinkingOption(_ option: ModelThinkingOption) {
        runtimeConfigurationResolver.setSelectedThinkingOption(
            option,
            fallbackModelIdentifier: chatConfiguration.modelIdentifier
        )
        syncChatConfigurationFromSettingsIfNeeded()
        objectWillChange.send()
    }

    func toggleCurrentThinking() {
        runtimeConfigurationResolver.toggleSelectedThinking(
            fallbackModelIdentifier: chatConfiguration.modelIdentifier
        )
        syncChatConfigurationFromSettingsIfNeeded()
        objectWillChange.send()
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

    // MARK: - Chat service wiring

    private func bindStreamingSession() {
        textRequestRuntime.bindStreamingHandlers(
            onDelta: { [weak self] piece in
                guard let self = self else { return }
                self.handleAssistantDelta(piece)
                self.realtimeNarrationCoordinator.appendDelta(piece)
            },
            onError: { [weak self] error in
                self?.handleChatServiceError(error)
            },
            onToolActivity: { [weak self] activity in
                self?.handleToolActivity(activity)
            },
            onStreamFinished: { [weak self] in
                self?.handleChatStreamFinished()
            }
        )
    }

    private func bindRequestActivityController() {
        textRequestRuntime.bindActivityState { [weak self] state in
            self?.isLoading = state.isLoading
            self?.isPriming = state.isPriming
        }
    }

    private func bindStreamRetryStatusController() {
        textRequestRuntime.bindRetryState { [weak self] state in
            self?.isRetrying = state.isRetrying
            self?.retryAttempt = state.retryAttempt
            self?.retryLastError = state.retryLastError
        }
    }

    private func handleChatServiceError(_ error: Error) {
        let now = Date()
        let errorText = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if shouldAutoRetryAfterError(error) {
            scheduleAutoRetry(after: error, errorText: errorText)
            return
        }

        let completion = textRequestRuntime.completeAfterError(error, in: chatSession, now: now)

        if !completion.errorText.isEmpty {
            requestDidFail.send(completion.errorText)
        }
        clearProcessingToolActivitiesFromMessages()
        clearTerminalToolActivitiesAfterDelay()

        let err = completion.errorMessage
        if let interrupted = completion.interruptedMessage {
            err.parentMessage = interrupted
            interrupted.activeChildMessageID = err.id
        } else if let parentID = completion.pendingParentMessageID,
                  let parent = messageLookup()[parentID] {
            err.parentMessage = parent
            parent.activeChildMessageID = err.id
        }
        chatSession.messages.append(err)
        markSessionMessageActivity(at: err.createdAt)
        invalidateCachesAfterMessageMutation()
        branchRestartCoordinator.clearPendingRestore()
        publishBranchChange()
        persistSession(reason: .immediate)

        realtimeNarrationCoordinator.finishActiveStream(flushingBufferedText: false)

        applyDeferredChatConfigurationIfNeeded()
        scheduleQueuedDraftAutostartIfNeeded()
    }

    private func handleChatStreamFinished() {
        let finishedAt = Date()
        textRequestRuntime.completeSuccessfully(in: chatSession, finishedAt: finishedAt)
        clearProcessingToolActivitiesFromMessages()
        clearToolActivities()

        branchRestartCoordinator.clearPendingRestore()

        persistSession(reason: .immediate)

        realtimeNarrationCoordinator.finishActiveStream(flushingBufferedText: true)

        applyDeferredChatConfigurationIfNeeded()
        scheduleQueuedDraftAutostartIfNeeded()
    }

    private func handleToolActivity(_ activity: ChatToolActivity) {
        let message = ensureAssistantMessageForToolActivity()
        if let index = toolActivities.firstIndex(where: { $0.id == activity.id }) {
            toolActivities[index] = activity
        } else {
            toolActivities.append(activity)
        }
        guard let message else { return }
        var activities = messageToolActivities[message.id] ?? []
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
        messageToolActivities[message.id] = activities
        var placements = messageToolActivityPlacements[message.id] ?? []
        if let index = placements.firstIndex(where: { $0.id == activity.id }) {
            placements[index].activity = activity
        } else {
            placements.append(makeToolActivityPlacement(activity, in: message))
        }
        messageToolActivityPlacements[message.id] = placements
        persistToolActivityPlacementsIfNeeded(placements, to: message)
        let fingerprint = ContentFingerprint.make(message.content)
        messageContentDidChange.send(.init(messageID: message.id, fingerprint: fingerprint))
    }

    private func clearToolActivities() {
        toolActivities.removeAll()
    }

    @discardableResult
    private func clearProcessingToolActivitiesFromMessages() -> Bool {
        var changedMessageIDs = Set<UUID>()

        if toolActivities.contains(where: { $0.phase == .processing }) {
            toolActivities.removeAll { $0.phase == .processing }
        }

        for messageID in Array(messageToolActivities.keys) {
            let activities = messageToolActivities[messageID] ?? []
            let filtered = activities.filter { $0.phase != .processing }
            guard filtered.count != activities.count else { continue }
            messageToolActivities[messageID] = filtered.isEmpty ? nil : filtered
            changedMessageIDs.insert(messageID)
        }

        for messageID in Array(messageToolActivityPlacements.keys) {
            let placements = messageToolActivityPlacements[messageID] ?? []
            let filtered = placements.filter { $0.activity.phase != .processing }
            guard filtered.count != placements.count else { continue }
            messageToolActivityPlacements[messageID] = filtered.isEmpty ? nil : filtered
            changedMessageIDs.insert(messageID)
        }

        guard !changedMessageIDs.isEmpty else { return false }
        let lookup = messageLookup()
        for messageID in changedMessageIDs {
            guard let message = lookup[messageID] else { continue }
            let fingerprint = ContentFingerprint.make(message.content)
            messageContentDidChange.send(.init(messageID: message.id, fingerprint: fingerprint))
        }
        return true
    }

    private func makeToolActivityPlacement(
        _ activity: ChatToolActivity,
        in message: ChatMessage
    ) -> ChatToolActivityPlacement {
        let parts = message.content.extractThinkParts()
        if let think = parts.think, parts.body.isEmpty {
            return ChatToolActivityPlacement(
                activity: activity,
                scope: .thinking,
                offset: think.count
            )
        }
        return ChatToolActivityPlacement(
            activity: activity,
            scope: .body,
            offset: parts.body.count
        )
    }

    private func persistToolActivityPlacementsIfNeeded(
        _ placements: [ChatToolActivityPlacement],
        to message: ChatMessage
    ) {
        let persistentPlacements = placements.filter { $0.activity.phase.isPersistentToolTracePhase }
        guard message.toolActivityPlacements != persistentPlacements else { return }
        message.toolActivityPlacements = persistentPlacements
        persistSession(reason: .throttled)
    }

    private func clearTerminalToolActivitiesAfterDelay() {
        guard !toolActivities.isEmpty else { return }
        let snapshot = toolActivities
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, self.toolActivities == snapshot else { return }
            self.toolActivities.removeAll()
        }
    }

    private func ensureAssistantMessageForToolActivity() -> ChatMessage? {
        if let id = currentAssistantMessageID, let existing = messageLookup()[id] {
            return existing
        }

        guard isPriming || isLoading || sending else {
            return nil
        }

        let now = Date()
        let appendResult = ChatAssistantDeltaAppender.append(
            piece: "",
            to: chatSession,
            currentAssistantMessageID: currentAssistantMessageID,
            pendingAssistantParentMessageID: pendingAssistantParentMessageID,
            streamingAssistantMessageID: streamingAssistantMessageID,
            streamingAssistantFingerprint: streamingAssistantFingerprint,
            messageLookup: messageLookup(),
            fallbackParent: { activeBranchMessages().last },
            now: now
        )
        if appendResult.didResolvePendingAssistantParent {
            pendingAssistantParentMessageID = nil
        }
        if appendResult.didCreateMessage {
            markSessionMessageActivity(at: appendResult.message.createdAt)
            invalidateCachesAfterMessageMutation()
            branchRestartCoordinator.clearPendingRestore()
            publishBranchChange()
            currentAssistantMessageID = appendResult.message.id
            streamingAssistantMessageID = appendResult.message.id
            streamingAssistantFingerprint = appendResult.fingerprint
            applyStreamMetadata(to: appendResult.message, firstTokenTimestamp: now)
            resetStreamingPersistenceState()
            persistSession(reason: .immediate)
        }
        return appendResult.message
    }

    /// Updates the configuration used by future requests.
    /// Active streams keep the snapshot they started with; settings edits are applied after they finish.
    func updateChatConfiguration(_ configuration: ChatServiceConfiguration) {
        let update = textRequestRuntime.updateConfiguration(configuration)
        guard update.didApply else { return }

        objectWillChange.send()
        scheduleQueuedDraftAutostartIfNeeded()
    }

    private func syncChatConfigurationFromSettingsIfNeeded() {
        updateChatConfiguration(runtimeConfigurationResolver.currentConfiguration())
    }

    private func applyDeferredChatConfigurationIfNeeded() {
        let update = textRequestRuntime.applyDeferredConfigurationIfIdle()
        if update.didApply {
            objectWillChange.send()
        }
    }

    // MARK: - Helpers (stable ordering & safe trimming)

    private func persistSession(reason: SessionPersistReason = .throttled) {
        sessionMutationController.persistSession(chatSession, reason: reason)
    }

    private func resetStreamingPersistenceState() { textRequestRuntime.resetStreamingPersistenceState() }

    private func markSessionMessageActivity(at date: Date) {
        sessionMutationController.markMessageActivity(in: chatSession, at: date)
    }
    private func invalidateBranchMessagesCache() { sessionMutationController.invalidateBranchMessagesCache() }
    private func invalidateMessageLookupCache() { sessionMutationController.invalidateMessageLookupCache() }
    private func invalidateCachesAfterMessageMutation() { sessionMutationController.invalidateAllCaches() }
    private func publishBranchChange() { sessionMutationController.publishBranchChange() }

    private func markRequestActive(pendingParentMessageID: UUID?) {
        textRequestRuntime.markActive(pendingParentMessageID: pendingParentMessageID)
    }

    private func markRequestInactive() {
        textRequestRuntime.markInactive()
    }

    private func prepareBranchRestart(from parent: ChatMessage) {
        _ = branchRestartCoordinator.prepareRestart(from: parent)
        invalidateBranchMessagesCache()
        publishBranchChange()
        markRequestActive(pendingParentMessageID: parent.id)
    }

    // MARK: - Telemetry

    private func recordStreamStart(
        using messages: [ChatMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) {
        textRequestRuntime.recordStreamStart(
            using: messages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )
    }

    private func applyStreamMetadata(to message: ChatMessage, firstTokenTimestamp: Date) {
        textRequestRuntime.applyStreamMetadata(
            to: message,
            firstTokenTimestamp: firstTokenTimestamp
        )
    }

    private func estimatedTokenCountFromCharacters(_ characterCount: Int) -> Int { textRequestRuntime.estimatedTokenCountFromCharacters(characterCount) }

    private func bumpStreamCounters(for message: ChatMessage, delta: String) { textRequestRuntime.bumpStreamCounters(for: message, delta: delta) }

    private func shouldForceImmediatePersist(afterAppending addedChars: Int) -> Bool { textRequestRuntime.shouldForceImmediatePersist(afterAppending: addedChars) }

    @discardableResult
    private func finalizeActiveAssistantMessage(reason: String, finishedAt: Date = Date(), errorDescription: String? = nil) -> ChatMessage? {
        textRequestRuntime.finalizeActiveAssistantMessage(
            in: chatSession,
            reason: reason,
            finishedAt: finishedAt,
            errorDescription: errorDescription
        )
    }

    private func messageLookup() -> [UUID: ChatMessage] {
        sessionMutationController.messageLookup(in: chatSession)
    }

    private func activeBranchMessages() -> [ChatMessage] {
        sessionMutationController.activeBranchMessages(in: chatSession)
    }

    /// Exposes the cached active branch chain for UI rendering.
    func orderedMessagesCached() -> [ChatMessage] { activeBranchMessages() }

    private func ensureMessageTreeInitializedIfNeeded() {
        sessionMutationController.repairMessageTreeIfNeeded(
            in: chatSession,
            isSending: sending,
            finalizeDanglingActiveAssistantMessages: { self.finalizeDanglingActiveAssistantMessagesIfNeeded() }
        )
    }

    @discardableResult
    private func finalizeDanglingActiveAssistantMessagesIfNeeded(now: Date = Date()) -> Bool {
        guard !sending else { return false }
        var didChange = false

        for message in chatSession.messages where !message.isUser && message.isActive {
            didChange = textRequestRuntime.finalizeDanglingActiveAssistantMessage(message, now: now) || didChange
        }

        if didChange {
            markRequestInactive()
        }
        return didChange
    }

    @discardableResult
    func send(
        draft: QueuedChatDraft,
        ignoringUnsupportedImageInputs: Bool,
        clearComposerAfterSend: Bool
    ) -> Bool {
        syncChatConfigurationFromSettingsIfNeeded()

        let supportsImageInputs = currentModelSupportsImageInput()
        let hasImageContext = activeBranchContainsImageInputs(includePending: !draft.imageAttachments.isEmpty)
        let turnResult = ChatConversationTurnController.startTurn(
            draft: draft,
            session: chatSession,
            hasActiveTextRequest: sending,
            supportsImageInputs: supportsImageInputs,
            hasImageInputContext: hasImageContext,
            ignoringUnsupportedImageInputs: ignoringUnsupportedImageInputs,
            clearComposerAfterSend: clearComposerAfterSend,
            prepareForAppend: {
                cancelQueuedDraftAutostart()
                resetRetryState()
                ensureMessageTreeInitializedIfNeeded()
            },
            fallbackParent: { activeBranchMessages().last },
            estimatedTokenCount: estimatedTokenCountFromCharacters
        )
        guard case let .accepted(turnStart) = turnResult else {
            return false
        }

        let userMsg = turnStart.userMessage
        clearToolActivities()
        if turnStart.shouldClearEditingBaseMessageID {
            editingBaseMessageID = nil
        }
        markSessionMessageActivity(at: userMsg.createdAt)
        invalidateCachesAfterMessageMutation()
        publishBranchChange()
        branchRestartCoordinator.clearPendingRestore()
        persistSession(reason: .immediate)

        finalizeActiveAssistantMessage(reason: "superseded", finishedAt: Date())
        markRequestActive(pendingParentMessageID: userMsg.id)
        if turnStart.shouldClearComposerAfterSend {
            clearQueuedDraftEditingState()
            clearComposerDraft()
        }

        let realtimeTTSActive = realtimeNarrationCoordinator.startPreparedStreamIfNeeded()

        startStreamingCurrentBranch(
            isVoiceMode: realtimeTTSActive || audioManager.isRealtimeMode,
            includeImagesInUserContent: supportsImageInputs
        )
        return true
    }

    private func startStreamingCurrentBranch(
        isVoiceMode: Bool,
        includeImagesInUserContent: Bool
    ) {
        let currentMessages = activeBranchMessages()
        let developerPrompt = runtimeConfigurationResolver.developerPrompt(isVoiceMode: isVoiceMode)
        recordStreamStart(
            using: currentMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )
        textRequestRuntime.fetchStreamedData(
            messages: currentMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )
    }

    // MARK: - Intent

    @discardableResult
    func sendRealtimeVoiceMessage(_ text: String, imageAttachments: [ChatImageAttachment] = []) -> Bool {
        let supportsImageInputs = currentModelSupportsImageInput()
        let hasExistingImageContext = activeBranchContainsImageInputs(includePending: false)

        let draftPlan = ChatRealtimeVoiceDraftPlanner.plan(
            text: text,
            imageAttachments: imageAttachments,
            supportsImageInputs: supportsImageInputs,
            hasExistingImageContext: hasExistingImageContext
        )
        guard case let .accepted(draft) = draftPlan else {
            if case let .rejected(userFacingError?) = draftPlan {
                requestDidFail.send(userFacingError)
            }
            return false
        }

        prepareRealtimeTTSForNextAssistant()
        let didSend = send(
            draft: draft,
            ignoringUnsupportedImageInputs: false,
            clearComposerAfterSend: false
        )
        if !didSend {
            realtimeNarrationCoordinator.cancelPreparedAssistant()
        }
        return didSend
    }

    func cancelCurrentRequest(autostartQueuedDraft: Bool = true) {
        guard sending || isLoading || isPriming else { return }
        let finishedAt = Date()
        cancelQueuedDraftAutostart()
        let completion = textRequestRuntime.cancelCurrentRequest(in: chatSession, finishedAt: finishedAt)

        let restore = branchRestartCoordinator.restorePendingBranchIfAssistantDidNotStart(
            currentAssistantMessageID: completion.assistantMessageIDForBranchRestore,
            messageLookup: messageLookup()
        )
        if restore.didRestoreBranch {
            invalidateBranchMessagesCache()
            publishBranchChange()
        }

        branchRestartCoordinator.clearPendingRestore()
        persistSession(reason: .immediate)
        clearProcessingToolActivitiesFromMessages()
        clearToolActivities()

        realtimeNarrationCoordinator.finishActiveStream(flushingBufferedText: false)

        applyDeferredChatConfigurationIfNeeded()
        if autostartQueuedDraft {
            scheduleQueuedDraftAutostartIfNeeded()
        }
    }

    private func handleAssistantDelta(_ piece: String) {
        guard isPriming || isLoading || sending else { return }
        clearProcessingToolActivitiesFromMessages()
        markRetryProgressIfNeeded()

        if isPriming {
            textRequestRuntime.markAssistantDeltaStarted()
        }
        let now = Date()

        let appendResult = ChatAssistantDeltaAppender.append(
            piece: piece,
            to: chatSession,
            currentAssistantMessageID: currentAssistantMessageID,
            pendingAssistantParentMessageID: pendingAssistantParentMessageID,
            streamingAssistantMessageID: streamingAssistantMessageID,
            streamingAssistantFingerprint: streamingAssistantFingerprint,
            messageLookup: messageLookup(),
            fallbackParent: { activeBranchMessages().last },
            now: now
        )
        if appendResult.didResolvePendingAssistantParent {
            pendingAssistantParentMessageID = nil
        }
        if appendResult.didCreateMessage {
            markSessionMessageActivity(at: appendResult.message.createdAt)
            invalidateCachesAfterMessageMutation()
            branchRestartCoordinator.clearPendingRestore()
            publishBranchChange()
            currentAssistantMessageID = appendResult.message.id
        }
        let message = appendResult.message
        let fingerprint = appendResult.fingerprint
        streamingAssistantMessageID = message.id
        streamingAssistantFingerprint = fingerprint

        applyStreamMetadata(to: message, firstTokenTimestamp: now)
        bumpStreamCounters(for: message, delta: piece)
        textRequestRuntime.markAssistantDeltaStarted()
        if appendResult.didCreateMessage {
            resetStreamingPersistenceState()
            persistSession(reason: .immediate)
        } else if shouldForceImmediatePersist(afterAppending: piece.count) {
            persistSession(reason: .immediate)
        } else {
            // Preserve streamed content durability across app suspends/crashes without
            // reintroducing per-token synchronous writes.
            persistSession(reason: .throttled)
        }
        messageContentDidChange.send(.init(messageID: message.id, fingerprint: fingerprint))
    }

    func regenerateSystemMessage(_ message: ChatMessage) {
        guard !sending else { return }
        syncChatConfigurationFromSettingsIfNeeded()
        ensureMessageTreeInitializedIfNeeded()
        textRequestRuntime.prepareForBranchRestart(in: chatSession, reason: "regenerate")

        guard !message.isUser else { return }
        guard let parent = message.parentMessage else { return }

        persistSession(reason: .immediate)

        prepareBranchRestart(from: parent)
        startStreamingCurrentBranch(
            isVoiceMode: audioManager.isRealtimeMode,
            includeImagesInUserContent: currentModelSupportsImageInput()
        )
    }

    func retry(afterErrorMessage errorMessage: ChatMessage) {
        guard !sending else { return }
        syncChatConfigurationFromSettingsIfNeeded()
        ensureMessageTreeInitializedIfNeeded()
        textRequestRuntime.prepareForBranchRestart(in: chatSession, reason: "retry")

        let active = activeBranchMessages()
        guard let errorIndex = active.firstIndex(where: { $0.id == errorMessage.id }) else { return }
        let priorMessages = active.prefix(errorIndex)
        guard let precedingUser = priorMessages.last(where: { $0.isUser }) else { return }

        persistSession(reason: .immediate)

        prepareBranchRestart(from: precedingUser)

        startStreamingCurrentBranch(
            isVoiceMode: audioManager.isRealtimeMode,
            includeImagesInUserContent: currentModelSupportsImageInput()
        )
    }

    func switchToMessageVersion(_ message: ChatMessage) {
        guard !sending else { return }
        ensureMessageTreeInitializedIfNeeded()
        sessionMutationController.switchToMessageVersion(message, in: chatSession, isSending: sending)
    }

    // MARK: - Auto Retry (Text Streaming)

    private func shouldAutoRetryAfterError(_ error: Error) -> Bool {
        textRequestRuntime.shouldAutoRetry(after: error)
    }

    private func scheduleAutoRetry(after error: Error, errorText: String) {
        textRequestRuntime.cancelScheduledRetry()

        // Keep the request "active" so the Stop button remains visible.
        textRequestRuntime.keepActiveForRetry()

        let plan = textRequestRuntime.planRetry(
            after: error,
            errorText: errorText,
            hasAssistantMessage: currentAssistantMessageID != nil
        )

        let delay = plan.delay
        let shouldUseVoicePrompt = realtimeNarrationCoordinator.shouldUseVoicePrompt
        let requestDeveloperPrompt = textRequestRuntime.activeDeveloperPrompt
            ?? runtimeConfigurationResolver.developerPrompt(isVoiceMode: shouldUseVoicePrompt)
        let includeImagesInUserContent = textRequestRuntime.activeTelemetry == nil
            ? currentModelSupportsImageInput()
            : textRequestRuntime.activeIncludeImagesInUserContent

        textRequestRuntime.scheduleRetry(after: delay) { [weak self] in
            self?.performScheduledAutoRetry(
                originalError: error,
                shouldUseVoicePrompt: shouldUseVoicePrompt,
                developerPrompt: requestDeveloperPrompt,
                includeImagesInUserContent: includeImagesInUserContent
            )
        }
    }

    private func performScheduledAutoRetry(
        originalError: Error,
        shouldUseVoicePrompt: Bool,
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) {
        guard isLoading || isPriming || sending else {
            resetRetryState()
            return
        }
        // Avoid silently switching prompt modes if the user changes modes between retries.
        if !shouldUseVoicePrompt && realtimeNarrationCoordinator.shouldUseVoicePrompt {
            resetRetryState()
            handleChatServiceError(originalError)
            return
        }

        let currentMessages = activeBranchMessages()
        textRequestRuntime.fetchStreamedData(
            messages: currentMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )
    }

    private func markRetryProgressIfNeeded() {
        textRequestRuntime.clearRetryStateAfterProgressIfNeeded()
    }

    private func resetRetryState() {
        textRequestRuntime.resetRetryState()
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
