//
//  ChatService+URLSessionDelegate.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension ChatService {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let currentTask = self.dataTask, dataTask === currentTask else {
            completionHandler(.cancel)
            return
        }
        markConnectionEstablishedIfNeeded()
        if let http = response as? HTTPURLResponse {
            httpStatusCode = http.statusCode
            if !(200...299).contains(http.statusCode) {
                errorResponseData.removeAll(keepingCapacity: true)
            }
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData _: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend _: Int64
    ) {
        guard let currentTask = self.dataTask, task === currentTask else { return }
        guard totalBytesSent > 0 else { return }
        markConnectionEstablishedIfNeeded()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let currentTask = self.dataTask, dataTask === currentTask else { return }
        guard !isCancelled else { return }
        markConnectionEstablishedIfNeeded()

        if let status = httpStatusCode, !(200...299).contains(status) {
            if errorResponseData.count < errorBodyCaptureLimit {
                let remaining = errorBodyCaptureLimit - errorResponseData.count
                errorResponseData.append(data.prefix(remaining))
            }
            return
        }

        if successResponseData.count < successBodyCaptureLimit {
            let remaining = successBodyCaptureLimit - successResponseData.count
            successResponseData.append(data.prefix(remaining))
        }

        let parserResult = sseParser.append(data)
        guard case let .frames(frames) = parserResult else {
            isCancelled = true
            dataTask.cancel()
            stopWatchdog()
            Task { @MainActor in
                self.onError?(ChatNetworkError.serverError(
                    statusCode: nil,
                    message: NSLocalizedString("Stream payload exceeded safety limit", comment: "Shown when streamed SSE data exceeds the configured memory safety cap")
                ))
            }
            return
        }

        for frame in frames {
            guard !isCancelled else { return }
            if frame.isDone {
                sseParser.clearPendingEventType()
                if newFormatActive && sentThinkOpen && !sentThinkClose && !isLegacyThinkStream {
                    emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                    sentThinkClose = true
                }
                if sawAnyPrimaryAssistantToken {
                    emitStreamFinishedOnce()
                    stopWatchdog()
                }
                return
            }

            guard let jsonData = frame.jsonData else { continue }
            let activeStyle = activeEndpointCandidate?.style ?? .openAIChatCompletions

            switch activeStyle {
            case .openAIChatCompletions:
                if handleOpenAICompatibleStreamPayload(jsonData, fallbackType: frame.eventType) {
                    sseParser.clearPendingEventType()
                }

            case .anthropicMessages:
                if let anthropicEvent = try? decoder.decode(AnthropicStreamEvent.self, from: jsonData),
                   anthropicEvent.type != nil {
                    sseParser.clearPendingEventType()
                    handleAnthropicStreamEvent(anthropicEvent)
                }

            case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
                if let lmStudioEvent = try? decoder.decode(LMStudioChatStreamEvent.self, from: jsonData) {
                    handleLMStudioStreamEvent(lmStudioEvent, fallbackType: frame.eventType)
                    sseParser.clearPendingEventType()
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let currentTask = self.dataTask, task === currentTask else { return }
        stopConnectionWatchdog()
        stopWatchdog()
        dataTask = nil
        endBackgroundExecutionForCurrentRequest()

        let activeStyle = activeEndpointCandidate?.style ?? .openAIChatCompletions
        let decision = ChatStreamCompletionRecovery.decide(
            isCancelled: isCancelled,
            httpStatusCode: httpStatusCode,
            error: error,
            errorResponseData: errorResponseData,
            successResponseData: successResponseData,
            sawAnyPrimaryAssistantToken: sawAnyPrimaryAssistantToken,
            activeStyle: activeStyle,
            pendingLMStudioStreamErrorMessage: pendingLMStudioStreamErrorMessage,
            bufferedResponseParser: bufferedResponseParser,
            streamPayloadExtractor: streamPayloadExtractor
        )

        if let metadata = decision.metadata {
            mergeResponseMetadata(metadata)
        }

        switch decision.outcome {
        case .ignore:
            return
        case .finish:
            emitStreamFinishedOnce()
        case let .recoveredText(text):
            emitDelta(text)
            emitStreamFinishedOnce()
        case let .serverError(statusCode, message):
            clearActiveEndpointCandidate()
            Task { @MainActor in
                self.onError?(ChatNetworkError.serverError(statusCode: statusCode, message: message))
            }
        case let .networkError(error):
            clearActiveEndpointCandidate()
            Task { @MainActor in self.onError?(error) }
        case .emptyResponse:
            clearActiveEndpointCandidate()
            Task { @MainActor in self.onError?(ChatNetworkError.emptyResponse) }
        }
    }
}
