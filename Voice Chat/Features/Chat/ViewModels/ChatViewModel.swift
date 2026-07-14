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

    private struct StreamAttemptRetryCheckpoint {
        let messageID: UUID?
        let content: String
        let assistantSegments: [ChatAssistantSegment]
        let openAIResponsesConversationItems: [JSONValue]
        let requestContentSnapshot: String?
        let toolActivityPlacements: [ChatToolActivityPlacement]
        let characterCount: Int
        let tokenCount: Int
        let tokenCountSource: String?
        let activeToolActivities: [ChatToolActivity]
        let messageToolActivities: [ChatToolActivity]
        let messageToolActivityPlacements: [ChatToolActivityPlacement]
        let telemetry: ChatAssistantStreamTelemetryRetryCheckpoint
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
    @Published private(set) var isToolContinuationLoading: Bool = false
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
    private var recordedRequestContextFingerprintsForActiveRequest = Set<String>()
    private var streamAttemptRetryCheckpoint: StreamAttemptRetryCheckpoint?

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
            onSegment: { [weak self] segment in
                self?.handleAssistantStreamSegment(segment)
            },
            onOpenAIResponsesConversationItems: { [weak self] items in
                self?.handleOpenAIResponsesConversationItems(items)
            },
            onError: { [weak self] error in
                self?.handleChatServiceError(error)
            },
            onResponseMetadata: { [weak self] metadata in
                self?.handleResponseMetadata(metadata)
            },
            onToolActivity: { [weak self] activity in
                self?.handleToolActivity(activity)
            },
            onStreamFinished: { [weak self] in
                self?.handleChatStreamFinished()
            }
        )
    }

    private func handleResponseMetadata(_ metadata: ChatResponseMetadata) {
        applyRequestTransportMetadataToLatestUserMessage(metadata)

        guard let requestContext = metadata.requestContext else { return }
        guard !recordedRequestContextFingerprintsForActiveRequest.contains(requestContext.fingerprint) else {
            return
        }
        recordedRequestContextFingerprintsForActiveRequest.insert(requestContext.fingerprint)
        ChatRequestContextMetadataStore.record(requestContext, in: chatSession.modelContext)
    }

    private func applyRequestTransportMetadataToLatestUserMessage(_ metadata: ChatResponseMetadata) {
        guard metadata.requestContext != nil || metadata.requestUsedPreviousResponseID != nil else {
            return
        }
        guard let message = activeBranchMessages().last(where: \.isUser) else {
            return
        }

        var didChange = false
        if let fingerprint = metadata.requestContext?.fingerprint,
           !fingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           message.requestContextFingerprint != fingerprint {
            message.requestContextFingerprint = fingerprint
            didChange = true
        }
        if let usedPreviousResponseID = metadata.requestUsedPreviousResponseID,
           message.requestUsedPreviousResponseID != usedPreviousResponseID {
            message.requestUsedPreviousResponseID = usedPreviousResponseID
            didChange = true
        }
        if metadata.requestUsedPreviousResponseID == false,
           message.requestPreviousResponseID != nil {
            message.requestPreviousResponseID = nil
            didChange = true
        }
        if metadata.requestUsedPreviousResponseID != false,
           let previousResponseID = metadata.requestPreviousResponseID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !previousResponseID.isEmpty,
           message.requestPreviousResponseID != previousResponseID {
            message.requestPreviousResponseID = previousResponseID
            if message.requestUsedPreviousResponseID == nil {
                message.requestUsedPreviousResponseID = true
            }
            didChange = true
        }

        if didChange {
            persistSession(reason: .throttled)
        }
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
        guard hasActiveTextRequest || isToolContinuationLoading else { return }
        let now = Date()
        let errorText = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        isToolContinuationLoading = false

        if let incomplete = error as? ChatIncompleteResponseError {
            restoreIncompleteResponse(incomplete)
            completeChatServiceError(incomplete, now: now)
            return
        }

        if textRequestRuntime.shouldAutoRetry(after: error) {
            rollbackStreamAttemptRetryCheckpointIfNeeded()
            realtimeNarrationCoordinator.restartActiveStreamForRetry()
            scheduleAutoRetry(after: error, errorText: errorText)
            return
        }

        completeChatServiceError(error, now: now)
    }

    private func restoreIncompleteResponse(_ error: ChatIncompleteResponseError) {
        rollbackStreamAttemptRetryCheckpointIfNeeded()
        if error.metadata.hasAnyValue {
            textRequestRuntime.mergeRecoveredResponseMetadata(error.metadata)
            handleResponseMetadata(error.metadata)
        }
        for segment in error.segments {
            handleAssistantStreamSegment(segment)
        }
    }

    private func completeChatServiceError(_ error: Error, now: Date = Date()) {
        streamAttemptRetryCheckpoint = nil
        refreshTrackedAssistantRequestSnapshotIfNeeded()
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
        isToolContinuationLoading = false
        streamAttemptRetryCheckpoint = nil
        refreshTrackedAssistantRequestSnapshotIfNeeded()
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
        if activity.phase == .processing {
            isToolContinuationLoading = true
            return
        }

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
        if activity.phase.isPersistentToolTracePhase {
            captureStreamAttemptRetryCheckpoint()
        }
        let fingerprint = ContentFingerprint.make(message.renderFingerprintSource)
        messageContentDidChange.send(.init(messageID: message.id, fingerprint: fingerprint))
    }

    private func handleOpenAIResponsesConversationItems(_ items: [JSONValue]) {
        guard canAcceptAssistantDelta,
              let message = ensureAssistantMessageForToolActivity(),
              message.openAIResponsesConversationItems != items else {
            return
        }
        message.openAIResponsesConversationItems = items
        captureStreamAttemptRetryCheckpoint()
        persistSession(reason: .immediate)
    }

    func resolveToolAuthorization(requestID: String, allowed: Bool) {
        textRequestRuntime.resolveToolAuthorization(requestID: requestID, allowed: allowed)
    }

    private func clearToolActivities() {
        isToolContinuationLoading = false
        toolActivities.removeAll()
    }

    private func captureStreamAttemptRetryCheckpoint() {
        let messageID = currentAssistantMessageID ?? streamingAssistantMessageID
        let message = messageID.flatMap { messageLookup()[$0] }
        streamAttemptRetryCheckpoint = StreamAttemptRetryCheckpoint(
            messageID: message?.id,
            content: message?.content ?? "",
            assistantSegments: message?.assistantSegments ?? [],
            openAIResponsesConversationItems: message?.openAIResponsesConversationItems ?? [],
            requestContentSnapshot: message?.requestContentSnapshot,
            toolActivityPlacements: message?.toolActivityPlacements ?? [],
            characterCount: message?.characterCount ?? 0,
            tokenCount: message?.tokenCount ?? 0,
            tokenCountSource: message?.tokenCountSource,
            activeToolActivities: toolActivities,
            messageToolActivities: message.flatMap { messageToolActivities[$0.id] } ?? [],
            messageToolActivityPlacements: message.flatMap { messageToolActivityPlacements[$0.id] } ?? [],
            telemetry: textRequestRuntime.makeTelemetryRetryCheckpoint()
        )
    }

    private func rollbackStreamAttemptRetryCheckpointIfNeeded() {
        guard let checkpoint = streamAttemptRetryCheckpoint else { return }
        textRequestRuntime.restoreTelemetryRetryCheckpoint(checkpoint.telemetry)
        let messageID = checkpoint.messageID ?? currentAssistantMessageID ?? streamingAssistantMessageID
        var didChange = toolActivities != checkpoint.activeToolActivities
        toolActivities = checkpoint.activeToolActivities

        guard let messageID, let message = messageLookup()[messageID] else {
            return
        }

        if messageToolActivities[messageID] != checkpoint.messageToolActivities {
            messageToolActivities[messageID] = checkpoint.messageToolActivities.isEmpty
                ? nil
                : checkpoint.messageToolActivities
            didChange = true
        }
        if messageToolActivityPlacements[messageID] != checkpoint.messageToolActivityPlacements {
            messageToolActivityPlacements[messageID] = checkpoint.messageToolActivityPlacements.isEmpty
                ? nil
                : checkpoint.messageToolActivityPlacements
            didChange = true
        }

        didChange = didChange ||
            message.content != checkpoint.content ||
            message.assistantSegments != checkpoint.assistantSegments ||
            message.openAIResponsesConversationItems != checkpoint.openAIResponsesConversationItems ||
            message.requestContentSnapshot != checkpoint.requestContentSnapshot ||
            message.toolActivityPlacements != checkpoint.toolActivityPlacements ||
            message.characterCount != checkpoint.characterCount ||
            message.tokenCount != checkpoint.tokenCount ||
            message.tokenCountSource != checkpoint.tokenCountSource
        guard didChange else { return }

        message.content = checkpoint.content
        message.assistantSegments = checkpoint.assistantSegments
        message.openAIResponsesConversationItems = checkpoint.openAIResponsesConversationItems
        message.requestContentSnapshot = checkpoint.requestContentSnapshot
        message.toolActivityPlacements = checkpoint.toolActivityPlacements
        message.characterCount = checkpoint.characterCount
        message.tokenCount = checkpoint.tokenCount
        message.tokenCountSource = checkpoint.tokenCountSource
        let fingerprint = ContentFingerprint.make(message.renderFingerprintSource)
        if streamingAssistantMessageID == message.id {
            streamingAssistantFingerprint = fingerprint
        }
        messageContentDidChange.send(.init(messageID: message.id, fingerprint: fingerprint))
        persistSession(reason: .immediate)
    }

    @discardableResult
    private func clearProcessingToolActivitiesFromMessages() -> Bool {
        var changedMessageIDs = Set<UUID>()

        if toolActivities.contains(where: { !$0.phase.isPersistentToolTracePhase }) {
            toolActivities.removeAll { !$0.phase.isPersistentToolTracePhase }
        }

        for messageID in Array(messageToolActivities.keys) {
            let activities = messageToolActivities[messageID] ?? []
            let filtered = activities.filter { $0.phase.isPersistentToolTracePhase }
            guard filtered.count != activities.count else { continue }
            messageToolActivities[messageID] = filtered.isEmpty ? nil : filtered
            changedMessageIDs.insert(messageID)
        }

        for messageID in Array(messageToolActivityPlacements.keys) {
            let placements = messageToolActivityPlacements[messageID] ?? []
            let filtered = placements.filter { $0.activity.phase.isPersistentToolTracePhase }
            guard filtered.count != placements.count else { continue }
            messageToolActivityPlacements[messageID] = filtered.isEmpty ? nil : filtered
            changedMessageIDs.insert(messageID)
        }

        guard !changedMessageIDs.isEmpty else { return false }
        let lookup = messageLookup()
        for messageID in changedMessageIDs {
            guard let message = lookup[messageID] else { continue }
            let fingerprint = ContentFingerprint.make(message.renderFingerprintSource)
            messageContentDidChange.send(.init(messageID: message.id, fingerprint: fingerprint))
        }
        return true
    }

    private func makeToolActivityPlacement(
        _ activity: ChatToolActivity,
        in message: ChatMessage
    ) -> ChatToolActivityPlacement {
        let assistantSegments = message.assistantSegments
        if !assistantSegments.isEmpty {
            return ChatToolActivityPlacementResolver.placement(
                for: activity,
                assistantSegments: assistantSegments
            )
        }

        let parts = message.content.extractThinkParts()
        return ChatToolActivityPlacementResolver.placement(
            for: activity,
            bodyText: parts.body,
            reasoningText: parts.think
        )
    }

    private func persistToolActivityPlacementsIfNeeded(
        _ placements: [ChatToolActivityPlacement],
        to message: ChatMessage
    ) {
        let persistentPlacements = placements.filter { $0.activity.phase.isPersistentToolTracePhase }
        let placementsChanged = message.toolActivityPlacements != persistentPlacements
        let snapshotChanged = ChatRequestPayloadProjector.refreshAssistantRequestSnapshotIfNeeded(
            message,
            placements: persistentPlacements
        )
        guard placementsChanged || snapshotChanged else { return }
        message.toolActivityPlacements = persistentPlacements
        persistSession(reason: .throttled)
    }

    private func refreshTrackedAssistantRequestSnapshotIfNeeded() {
        let messageID = currentAssistantMessageID ?? streamingAssistantMessageID
        guard let messageID, let message = messageLookup()[messageID] else { return }
        _ = ChatRequestPayloadProjector.refreshAssistantRequestSnapshotIfNeeded(message)
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
        recordedRequestContextFingerprintsForActiveRequest.removeAll(keepingCapacity: true)
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

    private func createPendingAssistantBranchPlaceholder(parent: ChatMessage) {
        guard currentAssistantMessageID == nil else { return }
        let placeholder = ChatMessage(
            content: "",
            isUser: false,
            isActive: true,
            createdAt: Date(),
            session: chatSession
        )
        placeholder.parentMessage = parent
        parent.activeChildMessageID = placeholder.id
        chatSession.messages.append(placeholder)
        currentAssistantMessageID = placeholder.id
        streamingAssistantMessageID = placeholder.id
        streamingAssistantFingerprint = ContentFingerprint.make("")
        pendingAssistantParentMessageID = nil
        markSessionMessageActivity(at: placeholder.createdAt)
        invalidateCachesAfterMessageMutation()
        branchRestartCoordinator.clearPendingRestore()
        publishBranchChange()
        persistSession(reason: .immediate)
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
        refreshTrackedAssistantRequestSnapshotIfNeeded()
        return textRequestRuntime.finalizeActiveAssistantMessage(
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

    private func requestMessages(through userMessage: ChatMessage) -> [ChatMessage]? {
        guard userMessage.isUser,
              let messages = sessionMutationController.messagesThrough(userMessage, in: chatSession),
              messages.last?.id == userMessage.id else {
            return nil
        }
        return messages
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
        var finalizedMessages: [ChatMessage] = []

        for message in chatSession.messages where !message.isUser && message.isActive {
            _ = ChatRequestPayloadProjector.refreshAssistantRequestSnapshotIfNeeded(message)
            if textRequestRuntime.finalizeDanglingActiveAssistantMessage(message, now: now) {
                finalizedMessages.append(message)
            }
        }

        if !finalizedMessages.isEmpty {
            appendInterruptionErrors(for: finalizedMessages, now: now)
            markRequestInactive()
            invalidateCachesAfterMessageMutation()
            publishBranchChange()
            persistSession(reason: .immediate)
        }
        return !finalizedMessages.isEmpty
    }

    private func appendInterruptionErrors(for messages: [ChatMessage], now: Date) {
        for message in messages where message.finishReason == "cancelled" || message.finishReason == "stopped" {
            guard message.activeChildMessageID == nil, message.childMessages.isEmpty else { continue }
            let alreadyHasErrorChild = message.childMessages.contains {
                $0.content.hasPrefix("!error:")
            }
            guard !alreadyHasErrorChild else { continue }
            let errorText = interruptionErrorText(for: message.finishReason)
            let error = ChatMessage(
                content: "!error:\(errorText)",
                isUser: false,
                isActive: false,
                createdAt: now,
                modelIdentifier: message.modelIdentifier,
                apiBaseURL: message.apiBaseURL,
                thinkingOptionRawValue: message.thinkingOptionRawValue,
                requestID: message.requestID,
                providerResponseID: message.providerResponseID,
                providerResponseIDs: message.providerResponseIDs,
                requestContextFingerprint: message.requestContextFingerprint,
                requestUsedPreviousResponseID: message.requestUsedPreviousResponseID,
                requestPreviousResponseID: message.requestPreviousResponseID,
                streamStartedAt: message.streamStartedAt,
                streamFirstTokenAt: message.streamFirstTokenAt,
                streamCompletedAt: now,
                timeToFirstToken: message.timeToFirstToken,
                streamDuration: message.streamDuration,
                generationDuration: message.generationDuration,
                outputTokenCount: message.outputTokenCount,
                reasoningOutputTokenCount: message.reasoningOutputTokenCount,
                tokensPerSecond: message.tokensPerSecond,
                deltaCount: message.tokenCount,
                tokenCountSource: message.tokenCountSource,
                timeToFirstTokenSource: message.timeToFirstTokenSource,
                tokensPerSecondSource: message.tokensPerSecondSource,
                finishReasonSource: ChatStreamMetricValueSource.local.rawValue,
                characterCount: errorText.count,
                promptMessageCount: message.promptMessageCount,
                promptCharacterCount: message.promptCharacterCount,
                finishReason: message.finishReason,
                errorDescription: errorText,
                session: chatSession,
                parentMessage: message
            )
            message.activeChildMessageID = error.id
            chatSession.messages.append(error)
        }
    }

    private func interruptionErrorText(for finishReason: String?) -> String {
        if finishReason == "stopped" {
            return NSLocalizedString(
                "Stopped.",
                comment: "Shown when an assistant response is stopped after output starts"
            )
        }
        return NSLocalizedString(
            "Cancelled.",
            comment: "Shown when an assistant response is cancelled before output starts"
        )
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
        startStreaming(
            messages: currentMessages,
            isVoiceMode: isVoiceMode,
            includeImagesInUserContent: includeImagesInUserContent
        )
    }

    private func startStreaming(
        messages currentMessages: [ChatMessage],
        isVoiceMode: Bool,
        includeImagesInUserContent: Bool
    ) {
        let developerPrompt = runtimeConfigurationResolver.developerPrompt(isVoiceMode: isVoiceMode)
        recordStreamStart(
            using: currentMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )
        captureStreamAttemptRetryCheckpoint()
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
        guard sending || isLoading || isPriming || isToolContinuationLoading else { return }
        let finishedAt = Date()
        isToolContinuationLoading = false
        streamAttemptRetryCheckpoint = nil
        cancelQueuedDraftAutostart()
        refreshTrackedAssistantRequestSnapshotIfNeeded()
        let completion = textRequestRuntime.cancelCurrentRequest(in: chatSession, finishedAt: finishedAt)

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

        branchRestartCoordinator.clearPendingRestore()
        markSessionMessageActivity(at: err.createdAt)
        invalidateCachesAfterMessageMutation()
        publishBranchChange()
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
        guard canAcceptAssistantDelta else { return }
        isToolContinuationLoading = false
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

    private func handleAssistantStreamSegment(_ segment: AssistantStreamSegment) {
        guard canAcceptAssistantDelta else { return }
        isToolContinuationLoading = false
        clearProcessingToolActivitiesFromMessages()
        markRetryProgressIfNeeded()

        if isPriming {
            textRequestRuntime.markAssistantDeltaStarted()
        }
        let now = Date()
        let mirrorPiece: String
        let countedPiece: String
        switch segment {
        case let .text(_, text):
            mirrorPiece = text
            countedPiece = text
        case let .reasoning(_, text):
            mirrorPiece = ""
            countedPiece = text
        case .tool:
            mirrorPiece = ""
            countedPiece = ""
        }

        let appendResult = ChatAssistantDeltaAppender.append(
            piece: mirrorPiece,
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
        message.appendAssistantSegment(segment)
        let segmentFingerprintComponent: String
        switch segment {
        case let .reasoning(id, text):
            segmentFingerprintComponent = "\u{1D}reasoning:\(id ?? ""):\(text)"
        case let .text(id, text):
            segmentFingerprintComponent = "\u{1D}text:\(id ?? ""):\(text)"
        case .tool:
            segmentFingerprintComponent = ""
        }
        let fingerprint = appendResult.fingerprint.appending(segmentFingerprintComponent)
        streamingAssistantMessageID = message.id
        streamingAssistantFingerprint = fingerprint

        applyStreamMetadata(to: message, firstTokenTimestamp: now)
        if !countedPiece.isEmpty {
            bumpStreamCounters(for: message, delta: countedPiece)
        }
        textRequestRuntime.markAssistantDeltaStarted()
        if case let .text(_, text) = segment, !text.isEmpty {
            realtimeNarrationCoordinator.appendDelta(text)
        }
        if appendResult.didCreateMessage {
            resetStreamingPersistenceState()
            persistSession(reason: .immediate)
        } else if shouldForceImmediatePersist(afterAppending: countedPiece.count) {
            persistSession(reason: .immediate)
        } else {
            persistSession(reason: .throttled)
        }
        messageContentDidChange.send(.init(messageID: message.id, fingerprint: fingerprint))
    }

    private var canAcceptAssistantDelta: Bool {
        isPriming ||
        isLoading ||
        sending ||
        isToolContinuationLoading ||
        currentAssistantMessageID != nil ||
        streamingAssistantMessageID != nil
    }

    func regenerateSystemMessage(_ message: ChatMessage) {
        guard !sending else { return }
        syncChatConfigurationFromSettingsIfNeeded()
        ensureMessageTreeInitializedIfNeeded()
        guard !message.isUser,
              let parent = message.parentMessage,
              let requestMessages = requestMessages(through: parent) else {
            return
        }

        textRequestRuntime.prepareForBranchRestart(in: chatSession, reason: "regenerate")
        persistSession(reason: .immediate)

        prepareBranchRestart(from: parent)
        createPendingAssistantBranchPlaceholder(parent: parent)
        startStreaming(
            messages: requestMessages,
            isVoiceMode: audioManager.isRealtimeMode,
            includeImagesInUserContent: currentModelSupportsImageInput()
        )
    }

    func retry(afterErrorMessage errorMessage: ChatMessage) {
        guard !sending else { return }
        syncChatConfigurationFromSettingsIfNeeded()
        ensureMessageTreeInitializedIfNeeded()
        guard !errorMessage.isUser,
              let errorLineage = sessionMutationController.messagesThrough(errorMessage, in: chatSession),
              let precedingUser = errorLineage.dropLast().last(where: \.isUser),
              let requestMessages = requestMessages(through: precedingUser) else {
            return
        }

        textRequestRuntime.prepareForBranchRestart(in: chatSession, reason: "retry")
        persistSession(reason: .immediate)

        prepareBranchRestart(from: precedingUser)
        createPendingAssistantBranchPlaceholder(parent: precedingUser)
        startStreaming(
            messages: requestMessages,
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

        textRequestRuntime.scheduleRetry(after: delay) { [weak self] in
            self?.performScheduledAutoRetry(originalError: error)
        }
    }

    private func performScheduledAutoRetry(originalError: Error) {
        guard isLoading || isPriming || sending || isToolContinuationLoading else {
            resetRetryState()
            return
        }
        if textRequestRuntime.retryLastFailedStreamRequest() {
            return
        }

        resetRetryState()
        completeChatServiceError(originalError)
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

enum ChatToolActivityPlacementResolver {
    static func placement(
        for activity: ChatToolActivity,
        assistantSegments: [ChatAssistantSegment]
    ) -> ChatToolActivityPlacement {
        guard let segmentIndex = assistantSegments.indices.last else {
            return ChatToolActivityPlacement(activity: activity, scope: .body, offset: 0)
        }
        let segment = assistantSegments[segmentIndex]
        let scope: ChatToolActivityScope = segment.kind == .reasoning ? .thinking : .body
        let aggregateOffset = assistantSegments.lazy
            .filter { $0.kind == segment.kind }
            .reduce(into: 0) { $0 += $1.text.count }
        return ChatToolActivityPlacement(
            activity: activity,
            scope: scope,
            offset: aggregateOffset,
            assistantSegmentAnchor: ChatAssistantSegmentAnchor(
                segmentIndex: segmentIndex,
                characterOffset: segment.text.count
            )
        )
    }

    static func placement(
        for activity: ChatToolActivity,
        bodyText: String,
        reasoningText: String?
    ) -> ChatToolActivityPlacement {
        let reasoningText = reasoningText ?? ""
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReasoning = reasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty, !trimmedReasoning.isEmpty {
            return ChatToolActivityPlacement(
                activity: activity,
                scope: .thinking,
                offset: reasoningText.count
            )
        }
        return ChatToolActivityPlacement(
            activity: activity,
            scope: .body,
            offset: bodyText.count,
            assistantSegmentAnchor: trimmedBody.isEmpty && trimmedReasoning.isEmpty
                ? ChatAssistantSegmentAnchor(segmentIndex: 0, characterOffset: 0)
                : nil
        )
    }
}
