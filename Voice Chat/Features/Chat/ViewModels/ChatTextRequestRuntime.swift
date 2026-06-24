//
//  ChatTextRequestRuntime.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation

struct ChatTextRequestErrorCompletion {
    let errorText: String
    let interruptedMessage: ChatMessage?
    let pendingParentMessageID: UUID?
    let errorMessage: ChatMessage
}

struct ChatTextRequestCancellationCompletion {
    let assistantMessageIDForBranchRestore: UUID?
}

@MainActor
final class ChatTextRequestRuntime {
    private let streamingSession: ChatStreamingSessionCoordinator
    private let requestActivityController = ChatRequestActivityController()
    private let streamRetryStatusController = ChatStreamRetryStatusController()
    private var streamTelemetryCoordinator = ChatAssistantStreamTelemetryCoordinator()

    var streamingAssistantMessageID: UUID?
    var streamingAssistantFingerprint: ContentFingerprint?

    init(
        configuration: ChatServiceConfiguration,
        service: ChatStreamingService?,
        serviceFactory: @escaping (ChatServiceConfiguring) -> ChatStreamingService
    ) {
        self.streamingSession = ChatStreamingSessionCoordinator(
            configuration: configuration,
            service: service,
            serviceFactory: serviceFactory
        )
    }

    var configuration: ChatServiceConfiguration { streamingSession.configuration }
    var sending: Bool { requestActivityController.sending }
    var hasActiveTextRequest: Bool { requestActivityController.hasActiveTextRequest }

    var currentAssistantMessageID: UUID? {
        get { requestActivityController.currentAssistantMessageID }
        set { requestActivityController.currentAssistantMessageID = newValue }
    }

    var interruptedAssistantMessageID: UUID? {
        get { requestActivityController.interruptedAssistantMessageID }
        set { requestActivityController.interruptedAssistantMessageID = newValue }
    }

    var pendingAssistantParentMessageID: UUID? {
        get { requestActivityController.pendingAssistantParentMessageID }
        set { requestActivityController.pendingAssistantParentMessageID = newValue }
    }

    var activeTelemetry: ChatAssistantStreamTelemetry? {
        streamTelemetryCoordinator.activeTelemetry
    }

    var activeDeveloperPrompt: String? {
        streamTelemetryCoordinator.activeDeveloperPrompt
    }

    var activeIncludeImagesInUserContent: Bool {
        streamTelemetryCoordinator.activeIncludeImagesInUserContent
    }

    func bindStreamingHandlers(
        onDelta: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void,
        onToolActivity: @escaping (ChatToolActivity) -> Void,
        onStreamFinished: @escaping () -> Void
    ) {
        streamingSession.bindHandlers(
            onDelta: onDelta,
            onError: onError,
            onResponseMetadata: { [weak self] metadata in
                self?.streamTelemetryCoordinator.mergeServerMetadata(metadata)
            },
            onToolActivity: onToolActivity,
            onStreamFinished: onStreamFinished
        )
    }

    func bindActivityState(_ onChange: @escaping (ChatRequestActivityController.PublishedState) -> Void) {
        requestActivityController.onPublishedStateChange = onChange
        requestActivityController.publishCurrentState()
    }

    func bindRetryState(_ onChange: @escaping (ChatStreamRetryStatusController.PublishedState) -> Void) {
        streamRetryStatusController.onPublishedStateChange = onChange
        streamRetryStatusController.publishCurrentState()
    }

    func updateConfiguration(_ configuration: ChatServiceConfiguration) -> ChatStreamingConfigurationUpdate {
        streamingSession.updateConfiguration(
            configuration,
            isActiveTextRequest: hasActiveTextRequest
        )
    }

    func applyDeferredConfigurationIfIdle() -> ChatStreamingConfigurationUpdate {
        streamingSession.applyDeferredConfigurationIfIdle(isActiveTextRequest: hasActiveTextRequest)
    }

    func fetchStreamedData(
        messages: [ChatMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) {
        streamingSession.fetchStreamedData(
            messages: messages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )
    }

    func cancelStreaming() {
        streamingSession.cancelStreaming()
    }

    func markActive(pendingParentMessageID: UUID?) {
        requestActivityController.markActive(pendingParentMessageID: pendingParentMessageID)
    }

    func markInactive() {
        requestActivityController.markInactive()
    }

    func keepActiveForRetry() {
        requestActivityController.keepActiveForRetry()
    }

    func markAssistantDeltaStarted() {
        requestActivityController.markAssistantDeltaStarted()
    }

    func clearAssistantTracking() {
        requestActivityController.clearAssistantTracking()
    }

    func shouldAutoRetry(after error: Error) -> Bool {
        streamRetryStatusController.shouldAutoRetry(after: error)
    }

    func planRetry(
        after error: Error,
        errorText: String,
        hasAssistantMessage: Bool
    ) -> ChatStreamRetryPlan {
        streamRetryStatusController.planRetry(
            after: error,
            errorText: errorText,
            hasAssistantMessage: hasAssistantMessage
        )
    }

    func scheduleRetry(after delay: TimeInterval, retryAction: @escaping @MainActor () -> Void) {
        streamRetryStatusController.scheduleRetry(after: delay, retryAction: retryAction)
    }

    func cancelScheduledRetry() {
        streamRetryStatusController.cancelScheduledRetry()
    }

    func clearRetryStateAfterProgressIfNeeded() {
        streamRetryStatusController.clearStateAfterProgressIfNeeded()
    }

    func resetRetryState() {
        streamRetryStatusController.reset()
    }

    func resetStreamingPersistenceState() {
        streamTelemetryCoordinator.resetStreamingPersistenceState()
    }

    func recordStreamStart(
        using messages: [ChatMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) {
        streamTelemetryCoordinator.recordStreamStart(
            using: messages,
            configuration: configuration,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )
    }

    func applyStreamMetadata(to message: ChatMessage, firstTokenTimestamp: Date) {
        streamTelemetryCoordinator.applyStreamMetadata(
            to: message,
            firstTokenTimestamp: firstTokenTimestamp,
            fallbackConfiguration: configuration
        )
    }

    func estimatedTokenCountFromCharacters(_ characterCount: Int) -> Int {
        streamTelemetryCoordinator.estimatedTokenCountFromCharacters(characterCount)
    }

    func bumpStreamCounters(for message: ChatMessage, delta: String) {
        streamTelemetryCoordinator.bumpStreamCounters(for: message, delta: delta)
    }

    func shouldForceImmediatePersist(afterAppending addedChars: Int) -> Bool {
        streamTelemetryCoordinator.shouldForceImmediatePersist(afterAppending: addedChars)
    }

    @discardableResult
    func finalizeActiveAssistantMessage(
        in session: ChatSession,
        reason: String,
        finishedAt: Date,
        errorDescription: String?
    ) -> ChatMessage? {
        let message: ChatMessage?
        if let id = currentAssistantMessageID ?? interruptedAssistantMessageID {
            message = session.messages.first { $0.id == id }
        } else {
            message = nil
        }
        let finalized = streamTelemetryCoordinator.finalizeActiveAssistantMessage(
            message,
            reason: reason,
            finishedAt: finishedAt,
            errorDescription: errorDescription,
            fallbackConfiguration: configuration
        )
        if streamingAssistantMessageID == finalized?.id {
            streamingAssistantMessageID = nil
            streamingAssistantFingerprint = nil
        }
        return finalized
    }

    func finalizeDanglingActiveAssistantMessage(_ message: ChatMessage, now: Date) -> Bool {
        streamTelemetryCoordinator.finalizeDanglingActiveAssistantMessage(message, now: now)
    }

    func makeErrorMessage(
        errorText: String,
        fallbackErrorDescription: String,
        createdAt: Date,
        telemetry: ChatAssistantStreamTelemetry?,
        session: ChatSession
    ) -> ChatMessage {
        streamTelemetryCoordinator.makeErrorMessage(
            errorText: errorText,
            fallbackErrorDescription: fallbackErrorDescription,
            createdAt: createdAt,
            telemetry: telemetry,
            fallbackConfiguration: configuration,
            session: session
        )
    }

    func completeAfterError(
        _ error: Error,
        in session: ChatSession,
        now: Date = Date()
    ) -> ChatTextRequestErrorCompletion {
        let telemetry = activeTelemetry
        let errorText = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        markInactive()
        resetRetryState()

        let interrupted = finalizeActiveAssistantMessage(
            in: session,
            reason: "error",
            finishedAt: now,
            errorDescription: error.localizedDescription
        )
        interruptedAssistantMessageID = interrupted?.id
        currentAssistantMessageID = nil
        resetStreamingPersistenceState()

        let pendingParentID = pendingAssistantParentMessageID
        let errorMessage = makeErrorMessage(
            errorText: errorText,
            fallbackErrorDescription: error.localizedDescription,
            createdAt: now,
            telemetry: telemetry,
            session: session
        )
        pendingAssistantParentMessageID = nil

        return ChatTextRequestErrorCompletion(
            errorText: errorText,
            interruptedMessage: interrupted,
            pendingParentMessageID: pendingParentID,
            errorMessage: errorMessage
        )
    }

    @discardableResult
    func completeSuccessfully(
        in session: ChatSession,
        finishedAt: Date = Date()
    ) -> ChatMessage? {
        let completedMessage = finalizeActiveAssistantMessage(
            in: session,
            reason: "completed",
            finishedAt: finishedAt,
            errorDescription: nil
        )
        resetStreamingPersistenceState()
        markInactive()
        resetRetryState()
        clearAssistantTracking()
        return completedMessage
    }

    func cancelCurrentRequest(
        in session: ChatSession,
        finishedAt: Date = Date()
    ) -> ChatTextRequestCancellationCompletion {
        cancelScheduledRetry()
        cancelStreaming()
        finalizeActiveAssistantMessage(
            in: session,
            reason: "cancelled",
            finishedAt: finishedAt,
            errorDescription: nil
        )
        let assistantIDForBranchRestore = currentAssistantMessageID
        clearAssistantTracking()
        resetStreamingPersistenceState()
        markInactive()
        resetRetryState()

        return ChatTextRequestCancellationCompletion(
            assistantMessageIDForBranchRestore: assistantIDForBranchRestore
        )
    }

    func prepareForBranchRestart(
        in session: ChatSession,
        reason: String,
        finishedAt: Date = Date()
    ) {
        resetRetryState()
        cancelStreaming()
        finalizeActiveAssistantMessage(
            in: session,
            reason: reason,
            finishedAt: finishedAt,
            errorDescription: nil
        )
        clearAssistantTracking()
    }
}
