//
//  ChatService+StreamingLifecycle.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension ChatService {
    /// Builds the request and starts the URLSession stream on the serial state queue.
    func startStreaming(endpoint: ChatAPIEndpointCandidate, requestBodyData: Data) {
        let request = requestFactory.makeStreamingRequest(
            endpoint: endpoint,
            requestBodyData: requestBodyData,
            apiKey: configurationProvider.apiKey
        )

        streamStartAt = Date()
        didEstablishConnection = false
        lastDeltaAt = nil
        beginBackgroundExecutionForCurrentRequest()
        startWatchdog()
        startConnectionWatchdog()

        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }

    func resetStreamState() {
        isLegacyThinkStream = false
        sawAnyAssistantToken = false
        sawAnyPrimaryAssistantToken = false
        newFormatActive = false
        sentThinkOpen = false
        sentThinkClose = false
        streamFinishedEmitted = false
        lastProcessedSSESequenceNumber = nil
        reasoningDeltaItemIDs.removeAll(keepingCapacity: true)
        outputTextDeltaItemIDs.removeAll(keepingCapacity: true)
        anthropicStreamState = .init()
        sseParser.reset()
        streamStartAt = nil
        didEstablishConnection = false
        lastDeltaAt = nil
        httpStatusCode = nil
        errorResponseData.removeAll(keepingCapacity: true)
        successResponseData.removeAll(keepingCapacity: true)
        pendingLMStudioStreamErrorMessage = nil
        pendingResponseMetadata = .empty
        stopConnectionWatchdog()
        endBackgroundExecutionForCurrentRequest()
    }

    func clearActiveEndpointCandidate() {
        activeEndpointCandidate = nil
    }

    func mergeResponseMetadata(_ update: ChatResponseMetadata) {
        pendingResponseMetadata.merge(update)
        let snapshot = pendingResponseMetadata
        Task { @MainActor in self.onResponseMetadata?(snapshot) }
    }

    func failCurrentStreamWithServerError(
        _ message: String,
        statusCode: Int? = nil,
        includeHTTPStatus: Bool = true
    ) {
        isCancelled = true
        dataTask?.cancel()
        dataTask = nil
        stopConnectionWatchdog()
        stopWatchdog()
        clearActiveEndpointCandidate()
        endBackgroundExecutionForCurrentRequest()
        let resolvedStatusCode = includeHTTPStatus ? (statusCode ?? httpStatusCode) : statusCode
        Task { @MainActor in
            self.onError?(ChatNetworkError.serverError(statusCode: resolvedStatusCode, message: message))
        }
    }

    func emitDelta(_ piece: String, marksPrimaryOutput: Bool = true) {
        guard !isCancelled else { return }
        lastDeltaAt = Date()
        Task { @MainActor in self.onDelta?(piece) }
        sawAnyAssistantToken = true
        if marksPrimaryOutput {
            sawAnyPrimaryAssistantToken = true
        }
    }

    func emitStreamFinishedOnce() {
        guard !streamFinishedEmitted else { return }
        streamFinishedEmitted = true
        clearActiveEndpointCandidate()
        Task { @MainActor in self.onStreamFinished?() }
    }
}
