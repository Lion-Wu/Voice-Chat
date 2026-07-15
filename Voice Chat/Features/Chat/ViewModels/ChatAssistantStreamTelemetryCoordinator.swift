//
//  ChatAssistantStreamTelemetryCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

enum ChatStreamMetricValueSource: String {
    case local
    case provider
}

struct ChatAssistantStreamTelemetry {
    let streamID: UUID
    let startedAt: Date
    let modelIdentifier: String
    let apiBaseURL: String
    let thinkingOption: ModelThinkingOption?
    let developerPrompt: String?
    let includeImagesInUserContent: Bool
    let promptMessageCount: Int
    let promptCharacterCount: Int
    var firstTokenAt: Date?
}

struct ChatAssistantStreamTelemetryRetryCheckpoint {
    fileprivate let activeTelemetry: ChatAssistantStreamTelemetry?
    fileprivate let pendingServerMetadata: ChatResponseMetadata
    fileprivate let completedServerMetadata: ChatResponseMetadata
    fileprivate let currentResponseMetadata: ChatResponseMetadata
    fileprivate let currentResponseKey: String?
    fileprivate let orderedProviderResponseIDs: [String]
    fileprivate let observedResponseCount: Int
    fileprivate let pendingDeltaWriteBytes: Int
}

struct ChatAssistantStreamTelemetryCoordinator {
    private(set) var activeTelemetry: ChatAssistantStreamTelemetry?
    private var pendingServerMetadata: ChatResponseMetadata = .empty
    private var completedServerMetadata = ChatResponseMetadata.empty
    private var currentResponseMetadata = ChatResponseMetadata.empty
    private var currentResponseKey: String?
    private var orderedProviderResponseIDs: [String] = []
    private var observedResponseCount = 0
    private var pendingDeltaWriteBytes: Int = 0
    private let deltaPersistThreshold: Int

    init(deltaPersistThreshold: Int = 2048) {
        self.deltaPersistThreshold = deltaPersistThreshold
    }

    var activeDeveloperPrompt: String? {
        activeTelemetry?.developerPrompt
    }

    var activeIncludeImagesInUserContent: Bool {
        activeTelemetry?.includeImagesInUserContent ?? false
    }

    func makeRetryCheckpoint() -> ChatAssistantStreamTelemetryRetryCheckpoint {
        ChatAssistantStreamTelemetryRetryCheckpoint(
            activeTelemetry: activeTelemetry,
            pendingServerMetadata: pendingServerMetadata,
            completedServerMetadata: completedServerMetadata,
            currentResponseMetadata: currentResponseMetadata,
            currentResponseKey: currentResponseKey,
            orderedProviderResponseIDs: orderedProviderResponseIDs,
            observedResponseCount: observedResponseCount,
            pendingDeltaWriteBytes: pendingDeltaWriteBytes
        )
    }

    mutating func restoreRetryCheckpoint(_ checkpoint: ChatAssistantStreamTelemetryRetryCheckpoint) {
        var requestMetadata = ChatResponseMetadata.empty
        requestMetadata.requestContext = pendingServerMetadata.requestContext
        requestMetadata.requestUsedPreviousResponseID = pendingServerMetadata.requestUsedPreviousResponseID
        requestMetadata.requestPreviousResponseID = pendingServerMetadata.requestPreviousResponseID

        activeTelemetry = checkpoint.activeTelemetry
        pendingServerMetadata = checkpoint.pendingServerMetadata
        completedServerMetadata = checkpoint.completedServerMetadata
        currentResponseMetadata = checkpoint.currentResponseMetadata
        currentResponseKey = checkpoint.currentResponseKey
        orderedProviderResponseIDs = checkpoint.orderedProviderResponseIDs
        observedResponseCount = checkpoint.observedResponseCount
        pendingDeltaWriteBytes = checkpoint.pendingDeltaWriteBytes

        // The service emits request context after the UI checkpoint is captured. It belongs
        // to the retried request body, unlike response metadata from the failed attempt.
        currentResponseMetadata.merge(requestMetadata)
        pendingServerMetadata = combinedServerMetadata()
    }

    mutating func mergeServerMetadata(_ metadata: ChatResponseMetadata) {
        let responseKey = metadata.providerResponseID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let responseKey, !responseKey.isEmpty {
            if let currentResponseKey, currentResponseKey != responseKey {
                commitCurrentResponseMetadata()
                currentResponseMetadata = .empty
                observedResponseCount += 1
            } else if currentResponseKey == nil {
                observedResponseCount += 1
            }
            currentResponseKey = responseKey
            if orderedProviderResponseIDs.last != responseKey {
                orderedProviderResponseIDs.append(responseKey)
            }
        }

        currentResponseMetadata.merge(metadata)
        pendingServerMetadata = combinedServerMetadata()
    }

    mutating func resetStreamingPersistenceState() {
        pendingDeltaWriteBytes = 0
    }

    mutating func recordStreamStart(
        using messages: [ChatMessage],
        configuration: ChatServiceConfiguration,
        developerPrompt: String?,
        includeImagesInUserContent: Bool,
        startedAt: Date = Date(),
        streamID: UUID = UUID()
    ) {
        let eligibleMessages = messages.filter { !$0.content.hasPrefix("!error:") }
        let promptCharacterCount = eligibleMessages.reduce(into: 0) { partial, msg in
            partial += msg.content.count
        }
        resetStreamingPersistenceState()
        pendingServerMetadata = .empty
        completedServerMetadata = .empty
        currentResponseMetadata = .empty
        currentResponseKey = nil
        orderedProviderResponseIDs.removeAll(keepingCapacity: true)
        observedResponseCount = 0

        activeTelemetry = ChatAssistantStreamTelemetry(
            streamID: streamID,
            startedAt: startedAt,
            modelIdentifier: configuration.modelIdentifier,
            apiBaseURL: configuration.apiBaseURL,
            thinkingOption: configuration.thinkingOption,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent,
            promptMessageCount: eligibleMessages.count,
            promptCharacterCount: promptCharacterCount,
            firstTokenAt: nil
        )
    }

    mutating func applyStreamMetadata(
        to message: ChatMessage,
        firstTokenTimestamp: Date,
        fallbackConfiguration: ChatServiceConfiguration
    ) {
        if var telemetry = activeTelemetry {
            if message.streamStartedAt == nil {
                message.streamStartedAt = telemetry.startedAt
            }
            if message.modelIdentifier == nil {
                message.modelIdentifier = telemetry.modelIdentifier
            }
            if message.apiBaseURL == nil {
                message.apiBaseURL = telemetry.apiBaseURL
            }
            if message.thinkingOptionRawValue == nil {
                message.thinkingOption = telemetry.thinkingOption
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
                activeTelemetry = telemetry
            }
        } else {
            if message.streamStartedAt == nil {
                message.streamStartedAt = firstTokenTimestamp
            }
            if message.streamFirstTokenAt == nil {
                message.streamFirstTokenAt = firstTokenTimestamp
            }
            if message.modelIdentifier == nil {
                message.modelIdentifier = fallbackConfiguration.modelIdentifier
            }
            if message.apiBaseURL == nil {
                message.apiBaseURL = fallbackConfiguration.apiBaseURL
            }
            if message.thinkingOptionRawValue == nil {
                message.thinkingOption = fallbackConfiguration.thinkingOption
            }
        }
        if let start = message.streamStartedAt,
           let first = message.streamFirstTokenAt,
           message.timeToFirstToken == nil {
            message.timeToFirstToken = first.timeIntervalSince(start)
            if message.timeToFirstTokenSource == nil {
                message.timeToFirstTokenSource = ChatStreamMetricValueSource.local.rawValue
            }
        }
        applyRequestTransportMetadata(to: message)
    }

    func estimatedTokenCountFromCharacters(_ characterCount: Int) -> Int {
        guard characterCount > 0 else { return 0 }
        return Int((Double(characterCount) / 4.0).rounded(.up))
    }

    func bumpStreamCounters(for message: ChatMessage, delta: String) {
        message.characterCount += delta.count
        if message.tokenCountSource != ChatStreamMetricValueSource.provider.rawValue {
            message.tokenCount = estimatedTokenCountFromCharacters(message.characterCount)
            if message.tokenCount > 0 {
                message.tokenCountSource = ChatStreamMetricValueSource.local.rawValue
            }
        }
    }

    mutating func shouldForceImmediatePersist(afterAppending addedChars: Int) -> Bool {
        pendingDeltaWriteBytes += addedChars
        guard pendingDeltaWriteBytes >= deltaPersistThreshold else { return false }
        pendingDeltaWriteBytes = 0
        return true
    }

    @discardableResult
    mutating func finalizeActiveAssistantMessage(
        _ message: ChatMessage?,
        reason: String,
        finishedAt: Date,
        errorDescription: String?,
        fallbackConfiguration: ChatServiceConfiguration
    ) -> ChatMessage? {
        guard let message else {
            clearActiveStream()
            return nil
        }

        message.isActive = false
        if message.finishReason == nil {
            message.finishReason = reason
            if message.finishReasonSource == nil {
                message.finishReasonSource = ChatStreamMetricValueSource.local.rawValue
            }
        }
        if message.errorDescription == nil {
            message.errorDescription = errorDescription
        }

        if message.streamStartedAt == nil {
            message.streamStartedAt = activeTelemetry?.startedAt ?? message.createdAt
        }
        if message.modelIdentifier == nil {
            message.modelIdentifier = activeTelemetry?.modelIdentifier ?? fallbackConfiguration.modelIdentifier
        }
        if message.apiBaseURL == nil {
            message.apiBaseURL = activeTelemetry?.apiBaseURL ?? fallbackConfiguration.apiBaseURL
        }
        if message.requestID == nil {
            message.requestID = activeTelemetry?.streamID ?? UUID()
        }
        if message.promptMessageCount == nil {
            message.promptMessageCount = activeTelemetry?.promptMessageCount
        }
        if message.promptCharacterCount == nil {
            message.promptCharacterCount = activeTelemetry?.promptCharacterCount
        }
        if message.streamFirstTokenAt == nil, let first = activeTelemetry?.firstTokenAt {
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
        if message.tokenCountSource != ChatStreamMetricValueSource.provider.rawValue,
           message.tokenCount == 0,
           message.characterCount > 0 {
            message.tokenCount = estimatedTokenCountFromCharacters(message.characterCount)
            if message.tokenCount > 0 {
                message.tokenCountSource = ChatStreamMetricValueSource.local.rawValue
            }
        }
        applyServerMetadata(to: message)
        clearActiveStream()
        return message
    }

    func makeErrorMessage(
        errorText: String,
        fallbackErrorDescription: String,
        createdAt: Date,
        telemetry: ChatAssistantStreamTelemetry?,
        fallbackConfiguration: ChatServiceConfiguration,
        session: ChatSession
    ) -> ChatMessage {
        let content = "!error:\(errorText.isEmpty ? fallbackErrorDescription : errorText)"
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
            ? ChatStreamMetricValueSource.provider.rawValue
            : (resolvedTimeToFirstToken != nil ? ChatStreamMetricValueSource.local.rawValue : nil)

        let streamDuration = telemetry.map { createdAt.timeIntervalSince($0.startedAt) }
        let generationDuration: TimeInterval? = {
            guard let first = telemetry?.firstTokenAt else { return nil }
            return createdAt.timeIntervalSince(first)
        }()
        let resolvedTokenCount = max(0, pendingServerMetadata.outputTokenCount ?? 0)
        let resolvedTokenCountSource: String? =
            pendingServerMetadata.outputTokenCount != nil
            ? ChatStreamMetricValueSource.provider.rawValue
            : (resolvedTokenCount > 0 ? ChatStreamMetricValueSource.local.rawValue : nil)

        let message = ChatMessage(
            content: content,
            isUser: false,
            isActive: false,
            createdAt: createdAt,
            modelIdentifier: telemetry?.modelIdentifier ?? fallbackConfiguration.modelIdentifier,
            apiBaseURL: telemetry?.apiBaseURL ?? fallbackConfiguration.apiBaseURL,
            thinkingOptionRawValue: (telemetry?.thinkingOption ?? fallbackConfiguration.thinkingOption)?.rawValue,
            requestID: telemetry?.streamID,
            providerResponseID: pendingServerMetadata.providerResponseID,
            providerResponseIDs: orderedProviderResponseIDs,
            requestContextFingerprint: pendingServerMetadata.requestContext?.fingerprint,
            requestUsedPreviousResponseID: pendingServerMetadata.requestUsedPreviousResponseID,
            requestPreviousResponseID: pendingServerMetadata.requestPreviousResponseID,
            streamStartedAt: telemetry?.startedAt,
            streamFirstTokenAt: telemetry?.firstTokenAt,
            streamCompletedAt: createdAt,
            timeToFirstToken: resolvedTimeToFirstToken,
            streamDuration: streamDuration,
            generationDuration: generationDuration,
            reasoningOutputTokenCount: pendingServerMetadata.reasoningOutputTokenCount,
            tokensPerSecond: pendingServerMetadata.tokensPerSecond,
            deltaCount: resolvedTokenCount,
            tokenCountSource: resolvedTokenCountSource,
            timeToFirstTokenSource: resolvedTimeToFirstTokenSource,
            tokensPerSecondSource: pendingServerMetadata.tokensPerSecond != nil ? ChatStreamMetricValueSource.provider.rawValue : nil,
            finishReasonSource: ChatStreamMetricValueSource.local.rawValue,
            characterCount: content.count,
            promptMessageCount: telemetry?.promptMessageCount,
            promptCharacterCount: telemetry?.promptCharacterCount,
            finishReason: "error",
            errorDescription: errorText.isEmpty ? fallbackErrorDescription : errorText,
            session: session
        )
        if message.tokensPerSecond == nil,
           message.tokensPerSecondSource != ChatStreamMetricValueSource.provider.rawValue,
           message.tokenCount > 0,
           let generationDuration = message.generationDuration,
           generationDuration > 0 {
            message.tokensPerSecond = Double(message.tokenCount) / generationDuration
            message.tokensPerSecondSource = ChatStreamMetricValueSource.local.rawValue
        } else if message.tokensPerSecond != nil && message.tokensPerSecondSource == nil {
            message.tokensPerSecondSource = ChatStreamMetricValueSource.provider.rawValue
        }
        return message
    }

    @discardableResult
    func finalizeDanglingActiveAssistantMessage(_ message: ChatMessage, now: Date) -> Bool {
        guard !message.isUser, message.isActive else { return false }
        message.isActive = false
        if message.finishReason == nil {
            message.finishReason = message.hasAssistantOutput ? "stopped" : "cancelled"
            if message.finishReasonSource == nil {
                message.finishReasonSource = ChatStreamMetricValueSource.local.rawValue
            }
        }
        if message.errorDescription == nil {
            message.errorDescription = interruptionDisplayText(for: message.finishReason)
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
        if message.tokenCountSource != ChatStreamMetricValueSource.provider.rawValue,
           message.tokenCount == 0,
           message.characterCount > 0 {
            message.tokenCount = estimatedTokenCountFromCharacters(message.characterCount)
            if message.tokenCount > 0 {
                message.tokenCountSource = ChatStreamMetricValueSource.local.rawValue
            }
        }
        if message.timeToFirstToken != nil && message.timeToFirstTokenSource == nil {
            message.timeToFirstTokenSource = ChatStreamMetricValueSource.local.rawValue
        }
        if message.tokensPerSecond == nil,
           message.tokenCount > 0,
           let generationDuration = message.generationDuration,
           generationDuration > 0 {
            message.tokensPerSecond = Double(message.tokenCount) / generationDuration
            message.tokensPerSecondSource = ChatStreamMetricValueSource.local.rawValue
        }
        return true
    }

    private func applyServerMetadata(to message: ChatMessage) {
        let metadata = pendingServerMetadata
        if let responseID = metadata.providerResponseID,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message.providerResponseID = responseID
        }
        if !orderedProviderResponseIDs.isEmpty {
            message.providerResponseIDs = orderedProviderResponseIDs
        }
        if let fingerprint = metadata.requestContext?.fingerprint,
           !fingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message.requestContextFingerprint = fingerprint
        }
        applyRequestTransportMetadata(to: message)
        if let outputTokenCount = metadata.outputTokenCount {
            let normalizedOutputTokenCount = max(0, outputTokenCount)
            message.outputTokenCount = normalizedOutputTokenCount
            message.tokenCount = normalizedOutputTokenCount
            message.tokenCountSource = ChatStreamMetricValueSource.provider.rawValue
        }
        if let reasoningOutputTokenCount = metadata.reasoningOutputTokenCount {
            message.reasoningOutputTokenCount = reasoningOutputTokenCount
        }
        if shouldPreserveLocalTerminalFinishReason(message.finishReason) {
            if message.finishReasonSource == nil {
                message.finishReasonSource = ChatStreamMetricValueSource.local.rawValue
            }
        } else if let finishReason = metadata.finishReason,
                  !finishReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message.finishReason = finishReason
            message.finishReasonSource = ChatStreamMetricValueSource.provider.rawValue
        } else if message.finishReason != nil, message.finishReasonSource == nil {
            message.finishReasonSource = ChatStreamMetricValueSource.local.rawValue
        }

        if let apiTTF = metadata.timeToFirstTokenSeconds,
           apiTTF.isFinite,
           apiTTF >= 0 {
            message.timeToFirstToken = apiTTF
            message.timeToFirstTokenSource = ChatStreamMetricValueSource.provider.rawValue
            if let start = message.streamStartedAt {
                message.streamFirstTokenAt = start.addingTimeInterval(apiTTF)
            }
        } else if message.timeToFirstToken != nil, message.timeToFirstTokenSource == nil {
            message.timeToFirstTokenSource = ChatStreamMetricValueSource.local.rawValue
        }

        if observedResponseCount <= 1,
           let apiTPS = metadata.tokensPerSecond,
           apiTPS.isFinite,
           apiTPS >= 0 {
            message.tokensPerSecond = apiTPS
            message.tokensPerSecondSource = ChatStreamMetricValueSource.provider.rawValue
        } else if let outputTokens = (message.tokenCount > 0 ? message.tokenCount : nil),
                  let generationDuration = message.generationDuration,
                  generationDuration > 0 {
            message.tokensPerSecond = Double(outputTokens) / generationDuration
            message.tokensPerSecondSource = ChatStreamMetricValueSource.local.rawValue
        }

        if message.tokenCountSource == nil, message.tokenCount > 0 {
            message.tokenCountSource = ChatStreamMetricValueSource.local.rawValue
        }
    }

    private func applyRequestTransportMetadata(to message: ChatMessage) {
        let metadata = pendingServerMetadata
        if let usedPreviousResponseID = metadata.requestUsedPreviousResponseID {
            message.requestUsedPreviousResponseID = usedPreviousResponseID
            if !usedPreviousResponseID {
                message.requestPreviousResponseID = nil
            }
        }
        if metadata.requestUsedPreviousResponseID != false,
           let previousResponseID = metadata.requestPreviousResponseID,
           !previousResponseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message.requestPreviousResponseID = previousResponseID
            if message.requestUsedPreviousResponseID == nil {
                message.requestUsedPreviousResponseID = true
            }
        }
    }

    private mutating func clearActiveStream() {
        activeTelemetry = nil
        pendingServerMetadata = .empty
        completedServerMetadata = .empty
        currentResponseMetadata = .empty
        currentResponseKey = nil
        orderedProviderResponseIDs.removeAll(keepingCapacity: true)
        observedResponseCount = 0
    }

    private func interruptionDisplayText(for finishReason: String?) -> String {
        if finishReason == "stopped" {
            return NSLocalizedString(
                "Stopped.",
                comment: "Shown when an assistant response is stopped after output starts"
            )
        }
        return NSLocalizedString(
            "Cancelled.",
            comment: "Shown when an active assistant response is cancelled before output starts"
        )
    }

    private func shouldPreserveLocalTerminalFinishReason(_ finishReason: String?) -> Bool {
        switch finishReason {
        case "error", "cancelled", "stopped", "superseded":
            return true
        default:
            return false
        }
    }

    private mutating func commitCurrentResponseMetadata() {
        completedServerMetadata = combineServerMetadata(
            completedServerMetadata,
            currentResponseMetadata
        )
    }

    private func combinedServerMetadata() -> ChatResponseMetadata {
        combineServerMetadata(completedServerMetadata, currentResponseMetadata)
    }

    private func combineServerMetadata(
        _ completed: ChatResponseMetadata,
        _ current: ChatResponseMetadata
    ) -> ChatResponseMetadata {
        var combined = completed
        combined.merge(current)

        if completed.outputTokenCount != nil || current.outputTokenCount != nil {
            combined.outputTokenCount = max(0, completed.outputTokenCount ?? 0) + max(0, current.outputTokenCount ?? 0)
        }
        if completed.reasoningOutputTokenCount != nil || current.reasoningOutputTokenCount != nil {
            combined.reasoningOutputTokenCount =
                max(0, completed.reasoningOutputTokenCount ?? 0) + max(0, current.reasoningOutputTokenCount ?? 0)
        }
        if completed.timeToFirstTokenSeconds != nil, current.timeToFirstTokenSeconds != nil {
            combined.timeToFirstTokenSeconds = completed.timeToFirstTokenSeconds
        }
        if completed.tokensPerSecond != nil, current.tokensPerSecond != nil {
            combined.tokensPerSecond = current.tokensPerSecond
        }
        return combined
    }
}
