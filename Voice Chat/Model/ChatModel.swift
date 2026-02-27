//
//  ChatModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import Foundation

// MARK: - Streaming Chunk Models

struct ChatCompletionChunk: Codable {
    var id: String?
    var object: String?
    var created: Int?
    var model: String?
    var choices: [Choice]?
    var usage: ChatCompletionUsage?
    var timings: LlamaServerTimings?
}

struct Choice: Codable {
    var index: Int?
    var finish_reason: String?
    var delta: Delta?
}

struct ChatResponseMetadata: Sendable {
    var providerResponseID: String?
    var inputTokenCount: Int?
    var outputTokenCount: Int?
    var reasoningOutputTokenCount: Int?
    var tokensPerSecond: Double?
    var timeToFirstTokenSeconds: Double?
    var finishReason: String?

    static let empty = ChatResponseMetadata()

    var hasAnyValue: Bool {
        providerResponseID != nil ||
        inputTokenCount != nil ||
        outputTokenCount != nil ||
        reasoningOutputTokenCount != nil ||
        tokensPerSecond != nil ||
        timeToFirstTokenSeconds != nil ||
        finishReason != nil
    }

    mutating func merge(_ update: ChatResponseMetadata) {
        if let providerResponseID = update.providerResponseID,
           !providerResponseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.providerResponseID = providerResponseID
        }
        if let inputTokenCount = update.inputTokenCount {
            self.inputTokenCount = inputTokenCount
        }
        if let outputTokenCount = update.outputTokenCount {
            self.outputTokenCount = outputTokenCount
        }
        if let reasoningOutputTokenCount = update.reasoningOutputTokenCount {
            self.reasoningOutputTokenCount = reasoningOutputTokenCount
        }
        if let tokensPerSecond = update.tokensPerSecond, tokensPerSecond.isFinite, tokensPerSecond >= 0 {
            self.tokensPerSecond = tokensPerSecond
        }
        if let timeToFirstTokenSeconds = update.timeToFirstTokenSeconds,
           timeToFirstTokenSeconds.isFinite,
           timeToFirstTokenSeconds >= 0 {
            self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
        }
        if let finishReason = update.finishReason,
           !finishReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.finishReason = finishReason
        }
    }
}

struct ChatCompletionUsage: Codable {
    var prompt_tokens: Int?
    var completion_tokens: Int?
    var total_tokens: Int?
    var completion_tokens_details: ChatCompletionUsageDetails?
}

struct ChatCompletionUsageDetails: Codable {
    var reasoning_tokens: Int?
}

struct LlamaServerTimings: Codable {
    var cache_n: Int?
    var prompt_n: Int?
    var predicted_n: Int?
    var predicted_per_second: Double?
}

/// Decodes reasoning fields produced by LM Studio v0.3.23 and later.
struct ReasoningValue: Codable {
    let text: String

    init(from decoder: Decoder) throws {
        if let single = try? String(from: decoder) {
            self.text = single
            return
        }
        if let obj = try? AnyDict(from: decoder) {
            if let s = obj.dict["content"]?.stringValue ?? obj.dict["text"]?.stringValue {
                self.text = s
                return
            }
            let joined = obj.dict.values.compactMap { $0.stringValue }.joined()
            if !joined.isEmpty {
                self.text = joined
                return
            }
        }
        if let arr = try? [AnyDict](from: decoder) {
            let collected = arr.compactMap { item in
                item.dict["content"]?.stringValue ?? item.dict["text"]?.stringValue
            }.joined()
            self.text = collected
            return
        }
        self.text = ""
    }
}

struct AnyDecodable: Decodable {
    let value: Any

    var stringValue: String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            value = s
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let obj = try? AnyDict(from: decoder) {
            value = obj.dict
        } else if let arr = try? [AnyDecodable](from: decoder) {
            value = arr.map { $0.value }
        } else {
            value = NSNull()
        }
    }
}

fileprivate struct DynamicCodingKey: CodingKey {
    let stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
}

struct AnyDict: Decodable {
    let dict: [String: AnyDecodable]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var result: [String: AnyDecodable] = [:]
        for key in container.allKeys {
            result[key.stringValue] = try container.decode(AnyDecodable.self, forKey: key)
        }
        self.dict = result
    }
}

struct Delta: Codable {
    var role: String?
    var content: String?
    var reasoning: ReasoningValue?
}

/// LM Studio REST API stream event model (`/api/v1/chat`).
private struct LMStudioChatStreamEvent: Decodable {
    let type: String?
    let content: String?
    let delta: String?
    let text: String?
    let output_text: String?
    let stats: LMStudioChatStreamStats?
    let response_id: String?
    let error: LMStudioChatStreamErrorPayload?
    let result: LMStudioChatStreamResult?
    let response: LMStudioChatStreamCompletedResponse?
}

private struct LMStudioChatStreamErrorPayload: Decodable {
    let message: String?
}

private struct LMStudioChatStreamResult: Decodable {
    let output: [LMStudioChatStreamOutputItem]?
    let stats: LMStudioChatStreamStats?
    let response_id: String?
    let model_instance_id: String?

    var primaryMessageText: String {
        guard let output else { return "" }
        for item in output {
            let normalizedType = item.type?.lowercased()
            if normalizedType == "reasoning" || normalizedType == "tool_call" || normalizedType == "invalid_tool_call" {
                continue
            }
            let text = item.contentText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return ""
    }
}

private struct LMStudioChatStreamCompletedResponse: Decodable {
    let output: [LMStudioChatStreamOutputItem]?
    let output_text: String?
    let content: String?
    let text: String?
    let stats: LMStudioChatStreamStats?
    let response_id: String?

    var primaryMessageText: String {
        if let output_text, !output_text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return output_text
        }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }
        guard let output else { return "" }
        for item in output {
            let normalizedType = item.type?.lowercased()
            if normalizedType == "reasoning" || normalizedType == "tool_call" || normalizedType == "invalid_tool_call" {
                continue
            }
            let text = item.contentText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return ""
    }
}

private struct LMStudioChatStreamStats: Decodable {
    let input_tokens: Double?
    let total_output_tokens: Double?
    let reasoning_output_tokens: Double?
    let tokens_per_second: Double?
    let time_to_first_token_seconds: Double?
}

private struct LMStudioChatStreamOutputItem: Decodable {
    let type: String?
    let contentText: String

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case text
        case value
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)

        if let directText = try? container.decode(String.self, forKey: .content) {
            contentText = directText
            return
        }
        if let singlePart = try? container.decode(LMStudioChatStreamOutputContent.self, forKey: .content),
           let text = singlePart.primaryText {
            contentText = text
            return
        }
        if let parts = try? container.decode([LMStudioChatStreamOutputContent].self, forKey: .content) {
            contentText = parts.compactMap(\.primaryText).joined()
            return
        }
        if let fallback = try? container.decode(AnyDecodable.self, forKey: .content) {
            contentText = LMStudioChatStreamOutputItem.flattenUnknownContent(fallback.value)
            return
        }
        if let directText = try? container.decode(String.self, forKey: .text) {
            contentText = directText
            return
        }
        if let directValue = try? container.decode(String.self, forKey: .value) {
            contentText = directValue
            return
        }
        if let fallback = try? container.decode(AnyDecodable.self, forKey: .message) {
            contentText = LMStudioChatStreamOutputItem.flattenUnknownContent(fallback.value)
            return
        }

        contentText = ""
    }

    private static func flattenUnknownContent(_ value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let object = value as? [String: AnyDecodable] {
            if let text = object["text"]?.stringValue, !text.isEmpty {
                return text
            }
            if let text = object["content"]?.stringValue, !text.isEmpty {
                return text
            }
            return object.values.map { flattenUnknownContent($0.value) }.joined()
        }
        if let array = value as? [Any] {
            return array.map(flattenUnknownContent).joined()
        }
        return ""
    }
}

private struct LMStudioChatStreamOutputContent: Decodable {
    let type: String?
    let text: String?
    let content: String?
    let value: String?

    var primaryText: String? {
        for candidate in [text, content, value] {
            guard let candidate else { continue }
            if !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }
}

/// Anthropic SSE event model (`/v1/messages`).
private struct AnthropicStreamEvent: Decodable {
    let type: String?
    let delta: AnthropicStreamDelta?
    let content_block: AnthropicStreamContentBlock?
    let message: AnthropicStreamMessage?
    let usage: AnthropicStreamUsage?
    let error: AnthropicStreamErrorPayload?
}

private struct AnthropicStreamDelta: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
    let stop_reason: String?
}

private struct AnthropicStreamContentBlock: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
}

private struct AnthropicStreamErrorPayload: Decodable {
    let type: String?
    let message: String?
}

private struct AnthropicStreamUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
}

private struct AnthropicStreamMessage: Decodable {
    let id: String?
    let stop_reason: String?
    let usage: AnthropicStreamUsage?
}

enum ChatNetworkError: Error {
    case invalidURL
    case serverError(statusCode: Int?, message: String)
    case timeout(String)
    case emptyResponse
}

extension ChatNetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid API URL", comment: "Shown when the configured chat API URL is invalid")
        case .serverError(_, let message):
            return message
        case .timeout(let message):
            return message
        case .emptyResponse:
            return NSLocalizedString(
                "Server returned an empty response",
                comment: "Shown when the request completes without any assistant output"
            )
        }
    }
}

// MARK: - Configuration

/// Provides chat API configuration without tying the service to a global singleton.
protocol ChatServiceConfiguring {
    var apiBaseURL: String { get }
    var modelIdentifier: String { get }
    var apiKey: String { get }
    var providerHint: ChatProvider? { get }
    var requestStyleHint: ChatRequestStyle? { get }
}

/// Lightweight snapshot of chat configuration to avoid actor-hopping from main-actor singletons.
struct ChatServiceConfiguration: ChatServiceConfiguring, Equatable {
    let apiBaseURL: String
    let modelIdentifier: String
    let apiKey: String
    let providerHint: ChatProvider?
    let requestStyleHint: ChatRequestStyle?

    init(
        apiBaseURL: String,
        modelIdentifier: String,
        apiKey: String,
        providerHint: ChatProvider? = nil,
        requestStyleHint: ChatRequestStyle? = nil
    ) {
        self.apiBaseURL = apiBaseURL
        self.modelIdentifier = modelIdentifier
        self.apiKey = apiKey
        self.providerHint = providerHint
        self.requestStyleHint = requestStyleHint
    }
}

// MARK: - Service Contracts

@MainActor
protocol ChatStreamingService: AnyObject {
    var onDelta: (@MainActor (String) -> Void)? { get set }
    var onError: (@MainActor (Error) -> Void)? { get set }
    var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)? { get set }
    var onStreamFinished: (@MainActor () -> Void)? { get set }

    func fetchStreamedData(messages: [ChatMessage], developerPrompt: String?, includeImagesInUserContent: Bool)
    func cancelStreaming()
}

// MARK: - ChatService (Streaming)

final class ChatService: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let configurationProvider: ChatServiceConfiguring

    private let stateQueue: DispatchQueue
    private let sessionQueue: OperationQueue
    private let delegateProxy: DelegateProxy

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    /// Callbacks are explicitly constrained to run on the main actor.
    @MainActor var onDelta: (@MainActor (String) -> Void)?
    @MainActor var onError: (@MainActor (Error) -> Void)?
    @MainActor var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)?
    @MainActor var onStreamFinished: (@MainActor () -> Void)?

    // Reasoning / body state tracking
    private var isLegacyThinkStream = false
    private var sawAnyAssistantToken = false
    private var newFormatActive = false
    private var sentThinkOpen = false
    private var sentThinkClose = false
    private var streamFinishedEmitted = false

    // SSE parsing buffer
    private var ssePartialLine: String = ""
    private var ssePendingEventType: String?
    private let maxBufferedSSEBytes = 512 * 1024
    private let thinkOpenLine = "<think>\n"
    private let thinkCloseLine = "\n</think>\n"
    private let decoder = JSONDecoder()

    // Watchdog configuration to cover long-running sessions (up to ~1 hour).
    private let connectTimeout: TimeInterval = 8             // Fail fast if we can't establish a connection.
    private let firstTokenTimeout: TimeInterval = 3600        // Wait up to one hour for the first token.
    private let silentGapTimeout: TimeInterval  = 3600        // Allow up to one hour of silence between tokens.
    private var streamStartAt: Date?
    private var didEstablishConnection: Bool = false
    private var lastDeltaAt: Date?
    private var watchdog: DispatchSourceTimer?
    private var connectionWatchdog: DispatchSourceTimer?

    // Cancel flag to ignore any residual deltas after stopping.
    private var isCancelled: Bool = false

    // HTTP status/error accumulation for non-2xx responses.
    private var httpStatusCode: Int?
    private let errorBodyCaptureLimit = 32 * 1024
    private var errorResponseData = Data()
    private let successBodyCaptureLimit = 2 * 1024 * 1024
    private var successResponseData = Data()
    private var anthropicThinkingActive = false
    private var pendingLMStudioStreamErrorMessage: String?
    private var activeEndpointCandidate: ChatAPIEndpointCandidate?
    private var pendingResponseMetadata = ChatResponseMetadata.empty

    private final class DelegateProxy: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        weak var owner: ChatService?

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            owner?.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            owner?.urlSession(session, dataTask: dataTask, didReceive: data)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64,
            totalBytesExpectedToSend: Int64
        ) {
            owner?.urlSession(
                session,
                task: task,
                didSendBodyData: bytesSent,
                totalBytesSent: totalBytesSent,
                totalBytesExpectedToSend: totalBytesExpectedToSend
            )
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            owner?.urlSession(session, task: task, didCompleteWithError: error)
        }
    }

    init(configurationProvider: ChatServiceConfiguring) {
        self.configurationProvider = configurationProvider
        self.stateQueue = DispatchQueue(label: "VoiceChat.ChatService.state", qos: .userInitiated)
        let queue = OperationQueue()
        queue.name = "VoiceChat.ChatService.session"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.underlyingQueue = self.stateQueue
        self.sessionQueue = queue
        self.delegateProxy = DelegateProxy()
        super.init()
        self.delegateProxy.owner = self
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest  = 3900   // Adds a few minutes of headroom beyond one hour.
        configuration.timeoutIntervalForResource = 3900
        configuration.httpMaximumConnectionsPerHost = 1
        self.session = URLSession(configuration: configuration, delegate: delegateProxy, delegateQueue: sessionQueue)
    }

    deinit {
        session?.invalidateAndCancel()
        stopConnectionWatchdog()
        stopWatchdog()
    }

    /// Called on the main actor to avoid crossing actor boundaries with SwiftData models.
    @MainActor
    func fetchStreamedData(messages: [ChatMessage], developerPrompt: String?, includeImagesInUserContent: Bool) {
        let base = configurationProvider.apiBaseURL
        let model = configurationProvider.modelIdentifier
        var endpointCandidates = ChatAPIEndpointResolver.endpointCandidates(
            for: base,
            preferredProvider: configurationProvider.providerHint
        )
        if let providerHint = configurationProvider.providerHint, providerHint != .unknown {
            let providerMatched = endpointCandidates.filter { $0.provider == providerHint }
            if !providerMatched.isEmpty {
                endpointCandidates = providerMatched
            }
        }
        if let styleHint = configurationProvider.requestStyleHint {
            let styleMatched = endpointCandidates.filter { $0.style == styleHint }
            if !styleMatched.isEmpty {
                endpointCandidates = styleMatched
            }
        }
        endpointCandidates = prioritizeEndpointCandidates(
            endpointCandidates,
            preferredStyle: configurationProvider.requestStyleHint
        )
        guard let firstEndpoint = endpointCandidates.first else {
            onError?(ChatNetworkError.invalidURL)
            return
        }

        let payload = transformedMessagesForRequest(
            messages: messages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )

        let requestBodyData: Data
        do {
            requestBodyData = try buildRequestBodyData(
                model: model,
                messagePayload: payload,
                developerPrompt: developerPrompt,
                style: firstEndpoint.style
            )
        } catch {
            onError?(error)
            return
        }
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.dataTask?.cancel()
            self.dataTask = nil
            self.stopWatchdog()
            self.resetStreamState()
            self.isCancelled = false
            self.activeEndpointCandidate = firstEndpoint
            self.startStreaming(endpoint: firstEndpoint, requestBodyData: requestBodyData)
        }
    }

    /// Cancels the current streaming request.
    @MainActor
    func cancelStreaming() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.isCancelled = true
            self.dataTask?.cancel()
            self.dataTask = nil
            self.stopWatchdog()
            self.resetStreamState()
            self.clearActiveEndpointCandidate()
        }
    }

    /// Builds the request and starts the URLSession stream (non-async helper).
    private func startStreaming(endpoint: ChatAPIEndpointCandidate, requestBodyData: Data) {
        var request = URLRequest(url: endpoint.chatURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 3900 // Individual request timeout with extra buffer beyond one hour.
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("keep-alive", forHTTPHeaderField: "Connection")
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")

        applyAuthHeaders(to: &request, for: endpoint)

        request.httpBody = requestBodyData

        streamStartAt = Date()
        didEstablishConnection = false
        lastDeltaAt = nil
        startWatchdog()
        startConnectionWatchdog()

        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }

    private func normalizedAPIKeyForXAPIKeyHeader(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func applyAuthHeaders(to request: inout URLRequest, for endpoint: ChatAPIEndpointCandidate) {
        let rawKey = configurationProvider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch endpoint.style {
        case .anthropicMessages:
            let keyForHeader = normalizedAPIKeyForXAPIKeyHeader(rawKey)
            if !keyForHeader.isEmpty {
                request.setValue(keyForHeader, forHTTPHeaderField: "x-api-key")
            }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        case .openAIChatCompletions, .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            if !rawKey.isEmpty {
                let headerValue = rawKey.lowercased().hasPrefix("bearer ") ? rawKey : "Bearer \(rawKey)"
                request.setValue(headerValue, forHTTPHeaderField: "Authorization")
            }
        }
    }

    private func buildRequestBodyData(
        model: String,
        messagePayload: [[String: Any]],
        developerPrompt: String?,
        style: ChatRequestStyle
    ) throws -> Data {
        switch style {
        case .openAIChatCompletions:
            let requestBody: [String: Any] = [
                "model": model,
                "stream": true,
                "messages": messagePayload
            ]
            return try JSONSerialization.data(withJSONObject: requestBody, options: [])

        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            let lmStudioInput = lmStudioRESTInput(
                from: messagePayload,
                textDiscriminator: style == .lmStudioRESTV1LegacyMessage ? "message" : "text"
            )
            var requestBody: [String: Any] = [
                "model": model,
                "stream": true,
                "input": lmStudioInput
            ]
            if let prompt = developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
               !prompt.isEmpty {
                requestBody["system_prompt"] = prompt
            }
            return try JSONSerialization.data(withJSONObject: requestBody, options: [])

        case .anthropicMessages:
            var requestBody: [String: Any] = [
                "model": model,
                "stream": true,
                "max_tokens": 4096,
                "messages": anthropicMessagesInput(from: messagePayload)
            ]
            if let prompt = developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
               !prompt.isEmpty {
                requestBody["system"] = prompt
            }
            return try JSONSerialization.data(withJSONObject: requestBody, options: [])
        }
    }

    private func resetStreamState() {
        isLegacyThinkStream = false
        sawAnyAssistantToken = false
        newFormatActive = false
        sentThinkOpen = false
        sentThinkClose = false
        streamFinishedEmitted = false
        anthropicThinkingActive = false
        ssePartialLine = ""
        ssePendingEventType = nil
        streamStartAt = nil
        didEstablishConnection = false
        lastDeltaAt = nil
        httpStatusCode = nil
        errorResponseData.removeAll(keepingCapacity: true)
        successResponseData.removeAll(keepingCapacity: true)
        pendingLMStudioStreamErrorMessage = nil
        pendingResponseMetadata = .empty
        stopConnectionWatchdog()
    }

    private func clearActiveEndpointCandidate() {
        activeEndpointCandidate = nil
    }

    private func transformedMessagesForRequest(
        messages: [ChatMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) -> [[String: Any]] {
        var payload: [[String: Any]] = []
        if let prompt = developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            payload.append([
                "role": "developer",
                "content": prompt
            ])
        }

        for message in messages where !message.content.hasPrefix("!error:") {
            let role = message.isUser ? "user" : "assistant"
            let textContent = message.content
            let imageAttachments = includeImagesInUserContent ? message.imageAttachments : []

            if message.isUser, !imageAttachments.isEmpty {
                var parts: [[String: Any]] = []
                if !textContent.isEmpty {
                    parts.append([
                        "type": "text",
                        "text": textContent
                    ])
                }

                for attachment in imageAttachments where !attachment.data.isEmpty {
                    parts.append([
                        "type": "image_url",
                        "image_url": [
                            "url": attachment.dataURLString
                        ]
                    ])
                }

                if !parts.isEmpty {
                    payload.append([
                        "role": role,
                        "content": parts
                    ])
                    continue
                }
            }

            payload.append([
                "role": role,
                "content": textContent
            ])
        }
        return payload
    }

    private func lmStudioRESTInput(
        from messagePayload: [[String: Any]],
        textDiscriminator: String
    ) -> Any {
        var transcriptLines: [String] = []
        transcriptLines.reserveCapacity(messagePayload.count)

        var lastUserPayloadIndex: Int?
        for (index, item) in messagePayload.enumerated() {
            if (item["role"] as? String)?.lowercased() == "user" {
                lastUserPayloadIndex = index
            }
        }

        var latestUserImages: [[String: Any]] = []
        for (index, item) in messagePayload.enumerated() {
            let role = ((item["role"] as? String) ?? "user").lowercased()
            if role == "developer" || role == "system" {
                continue
            }

            var collectedText = ""
            var collectedImages: [[String: Any]] = []

            if let text = item["content"] as? String {
                collectedText = text
            } else if let parts = item["content"] as? [[String: Any]] {
                for part in parts {
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    if partType == "text" {
                        if let text = part["text"] as? String {
                            collectedText += text
                        }
                    } else if let dataURL = lmStudioRESTImageDataURL(from: part) {
                        collectedImages.append([
                            "type": "image",
                            "data_url": dataURL
                        ])
                    }
                }
            }

            let trimmedText = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                let speaker = role == "assistant" ? "Assistant" : "User"
                transcriptLines.append("\(speaker): \(trimmedText)")
            }

            if role == "user", index == lastUserPayloadIndex, !collectedImages.isEmpty {
                latestUserImages = collectedImages
            }
        }

        let transcript = transcriptLines.joined(separator: "\n\n")
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // LM Studio `/api/v1/chat` accepts plain strings, which avoids discriminator mismatches
        // when a text-only request is sent to different server versions.
        if latestUserImages.isEmpty {
            return trimmedTranscript.isEmpty ? "" : transcript
        }

        var input: [[String: Any]] = []
        if !trimmedTranscript.isEmpty {
            input.append([
                "type": textDiscriminator,
                "content": transcript
            ])
        }
        input.append(contentsOf: latestUserImages)
        return input
    }

    private func lmStudioRESTImageDataURL(from part: [String: Any]) -> String? {
        if let dataURL = part["data_url"] as? String,
           !dataURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dataURL
        }

        let partType = ((part["type"] as? String) ?? "").lowercased()
        guard partType == "image_url" else { return nil }

        guard let imageURL = part["image_url"] as? [String: Any],
              let urlString = imageURL["url"] as? String else {
            return nil
        }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDataURL(_ raw: String) -> (mimeType: String, base64Data: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("data:"),
              let separator = trimmed.firstIndex(of: ",") else {
            return nil
        }
        let header = String(trimmed[..<separator])
        let payload = String(trimmed[trimmed.index(after: separator)...])
        guard !payload.isEmpty else { return nil }

        let mediaAndEncoding = String(header.dropFirst("data:".count))
        let parts = mediaAndEncoding.split(separator: ";")
        guard let media = parts.first, !media.isEmpty else { return nil }
        let isBase64 = parts.dropFirst().contains { $0.caseInsensitiveCompare("base64") == .orderedSame }
        guard isBase64 else { return nil }
        return (mimeType: String(media), base64Data: payload)
    }

    private func anthropicMessagesInput(from messagePayload: [[String: Any]]) -> [[String: Any]] {
        var output: [[String: Any]] = []
        output.reserveCapacity(messagePayload.count)

        for item in messagePayload {
            let rawRole = ((item["role"] as? String) ?? "").lowercased()
            guard rawRole == "user" || rawRole == "assistant" else { continue }

            var contentParts: [[String: Any]] = []
            if let text = item["content"] as? String {
                if !text.isEmpty {
                    contentParts.append(["type": "text", "text": text])
                }
            } else if let parts = item["content"] as? [[String: Any]] {
                for part in parts {
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    if partType == "text" {
                        if let text = part["text"] as? String, !text.isEmpty {
                            contentParts.append(["type": "text", "text": text])
                        }
                        continue
                    }

                    guard let dataURL = lmStudioRESTImageDataURL(from: part),
                          let parsed = parseDataURL(dataURL) else {
                        continue
                    }
                    contentParts.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": parsed.mimeType,
                            "data": parsed.base64Data
                        ]
                    ])
                }
            }

            if contentParts.isEmpty {
                continue
            }
            output.append([
                "role": rawRole,
                "content": contentParts
            ])
        }

        if output.isEmpty {
            output.append([
                "role": "user",
                "content": [
                    ["type": "text", "text": ""]
                ]
            ])
        }
        return output
    }

    private func prioritizeEndpointCandidates(
        _ candidates: [ChatAPIEndpointCandidate],
        preferredStyle: ChatRequestStyle?
    ) -> [ChatAPIEndpointCandidate] {
        guard let preferredStyle else { return candidates }
        return candidates.enumerated().sorted { lhs, rhs in
            let lhsPreferred = lhs.element.style == preferredStyle
            let rhsPreferred = rhs.element.style == preferredStyle
            if lhsPreferred != rhsPreferred {
                return lhsPreferred && !rhsPreferred
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func normalizedTokenCount(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return Int(value.rounded())
    }

    private func mergeResponseMetadata(_ update: ChatResponseMetadata) {
        pendingResponseMetadata.merge(update)
        let snapshot = pendingResponseMetadata
        Task { @MainActor in self.onResponseMetadata?(snapshot) }
    }

    private func extractResponseMetadata(from dictionary: [String: Any], style: ChatRequestStyle) -> ChatResponseMetadata {
        switch style {
        case .openAIChatCompletions:
            var metadata = ChatResponseMetadata.empty
            if let responseID = dictionary["id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }
            if let usage = dictionary["usage"] as? [String: Any] {
                if let input = usage["prompt_tokens"] as? NSNumber {
                    metadata.inputTokenCount = input.intValue
                }
                if let output = usage["completion_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
                if let details = usage["completion_tokens_details"] as? [String: Any],
                   let reasoning = details["reasoning_tokens"] as? NSNumber {
                    metadata.reasoningOutputTokenCount = reasoning.intValue
                }
            }
            if let timings = dictionary["timings"] as? [String: Any] {
                if metadata.inputTokenCount == nil {
                    let promptN = (timings["prompt_n"] as? NSNumber)?.intValue ?? 0
                    let cacheN = (timings["cache_n"] as? NSNumber)?.intValue ?? 0
                    let totalPrompt = promptN + cacheN
                    if totalPrompt > 0 {
                        metadata.inputTokenCount = totalPrompt
                    }
                }
                if metadata.outputTokenCount == nil,
                   let predictedN = timings["predicted_n"] as? NSNumber {
                    metadata.outputTokenCount = predictedN.intValue
                }
                if metadata.tokensPerSecond == nil,
                   let predictedPerSecond = timings["predicted_per_second"] as? NSNumber {
                    metadata.tokensPerSecond = predictedPerSecond.doubleValue
                }
            }
            if let choices = dictionary["choices"] as? [[String: Any]],
               let first = choices.first,
               let finish = first["finish_reason"] as? String,
               !finish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = finish
            }
            return metadata

        case .anthropicMessages:
            var metadata = ChatResponseMetadata.empty
            if let responseID = dictionary["id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            } else if let message = dictionary["message"] as? [String: Any],
                      let responseID = message["id"] as? String,
                      !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }
            if let usage = dictionary["usage"] as? [String: Any] {
                if let input = usage["input_tokens"] as? NSNumber {
                    metadata.inputTokenCount = input.intValue
                }
                if let output = usage["output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
            } else if let message = dictionary["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] {
                if let input = usage["input_tokens"] as? NSNumber {
                    metadata.inputTokenCount = input.intValue
                }
                if let output = usage["output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
            }
            if let stopReason = dictionary["stop_reason"] as? String,
               !stopReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = stopReason
            } else if let message = dictionary["message"] as? [String: Any],
                      let stopReason = message["stop_reason"] as? String,
                      !stopReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = stopReason
            }
            return metadata

        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            var metadata = ChatResponseMetadata.empty
            if let responseID = dictionary["response_id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }

            if let stats = dictionary["stats"] as? [String: Any] {
                if let input = stats["input_tokens"] as? NSNumber {
                    metadata.inputTokenCount = input.intValue
                }
                if let output = stats["total_output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
                if let reasoning = stats["reasoning_output_tokens"] as? NSNumber {
                    metadata.reasoningOutputTokenCount = reasoning.intValue
                }
                if let tps = stats["tokens_per_second"] as? NSNumber {
                    metadata.tokensPerSecond = tps.doubleValue
                }
                if let ttf = stats["time_to_first_token_seconds"] as? NSNumber {
                    metadata.timeToFirstTokenSeconds = ttf.doubleValue
                }
            }

            if let result = dictionary["result"] as? [String: Any] {
                if metadata.providerResponseID == nil,
                   let responseID = result["response_id"] as? String,
                   !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metadata.providerResponseID = responseID
                }
                if let stats = result["stats"] as? [String: Any] {
                    if metadata.inputTokenCount == nil, let input = stats["input_tokens"] as? NSNumber {
                        metadata.inputTokenCount = input.intValue
                    }
                    if metadata.outputTokenCount == nil, let output = stats["total_output_tokens"] as? NSNumber {
                        metadata.outputTokenCount = output.intValue
                    }
                    if metadata.reasoningOutputTokenCount == nil, let reasoning = stats["reasoning_output_tokens"] as? NSNumber {
                        metadata.reasoningOutputTokenCount = reasoning.intValue
                    }
                    if metadata.tokensPerSecond == nil, let tps = stats["tokens_per_second"] as? NSNumber {
                        metadata.tokensPerSecond = tps.doubleValue
                    }
                    if metadata.timeToFirstTokenSeconds == nil, let ttf = stats["time_to_first_token_seconds"] as? NSNumber {
                        metadata.timeToFirstTokenSeconds = ttf.doubleValue
                    }
                }
            }

            if let response = dictionary["response"] as? [String: Any] {
                if metadata.providerResponseID == nil,
                   let responseID = response["response_id"] as? String,
                   !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metadata.providerResponseID = responseID
                }
                if let stats = response["stats"] as? [String: Any] {
                    if metadata.inputTokenCount == nil, let input = stats["input_tokens"] as? NSNumber {
                        metadata.inputTokenCount = input.intValue
                    }
                    if metadata.outputTokenCount == nil, let output = stats["total_output_tokens"] as? NSNumber {
                        metadata.outputTokenCount = output.intValue
                    }
                    if metadata.reasoningOutputTokenCount == nil, let reasoning = stats["reasoning_output_tokens"] as? NSNumber {
                        metadata.reasoningOutputTokenCount = reasoning.intValue
                    }
                    if metadata.tokensPerSecond == nil, let tps = stats["tokens_per_second"] as? NSNumber {
                        metadata.tokensPerSecond = tps.doubleValue
                    }
                    if metadata.timeToFirstTokenSeconds == nil, let ttf = stats["time_to_first_token_seconds"] as? NSNumber {
                        metadata.timeToFirstTokenSeconds = ttf.doubleValue
                    }
                }
            }
            return metadata
        }
    }

    private func parseBufferedSuccessResponse(_ data: Data, style: ChatRequestStyle) -> (text: String?, errorMessage: String?, metadata: ChatResponseMetadata) {
        guard !data.isEmpty else { return (nil, nil, .empty) }
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            return (nil, nil, .empty)
        }
        guard let first = raw.first, first == "{" || first == "[" else {
            // Likely SSE frames (`event:` / `data:`), not a plain JSON response body.
            return (nil, nil, .empty)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return (nil, nil, .empty)
        }
        let metadata = extractResponseMetadata(from: dictionary, style: style)

        if let errorObject = dictionary["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return (nil, trimmed, metadata)
            }
        }
        if let directMessage = dictionary["message"] as? String {
            let trimmed = directMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, dictionary["output"] == nil, dictionary["choices"] == nil {
                return (nil, trimmed, metadata)
            }
        }

        let recoveredText: String?
        switch style {
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            recoveredText = extractLMStudioAssistantText(from: dictionary)
        case .openAIChatCompletions:
            recoveredText = extractOpenAIAssistantText(from: dictionary)
        case .anthropicMessages:
            recoveredText = extractAnthropicAssistantText(from: dictionary)
        }

        if let text = recoveredText {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return (trimmed, nil, metadata)
            }
        }

        return (nil, nil, metadata)
    }

    private func extractLMStudioAssistantText(from dictionary: [String: Any]) -> String? {
        if let output = dictionary["output"] as? [[String: Any]],
           let text = extractLMStudioOutputText(output) {
            return text
        }

        if let result = dictionary["result"] as? [String: Any],
           let output = result["output"] as? [[String: Any]],
           let text = extractLMStudioOutputText(output) {
            return text
        }

        if let response = dictionary["response"] as? [String: Any],
           let output = response["output"] as? [[String: Any]],
           let text = extractLMStudioOutputText(output) {
            return text
        }

        return nil
    }

    private func extractOpenAIAssistantText(from dictionary: [String: Any]) -> String? {
        if let choices = dictionary["choices"] as? [[String: Any]] {
            for choice in choices {
                if let message = choice["message"] as? [String: Any],
                   let content = message["content"] {
                    let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                }
                if let delta = choice["delta"] as? [String: Any],
                   let content = delta["content"] {
                    let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                }
            }
        }

        if let content = dictionary["content"] {
            let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        if let message = dictionary["message"] as? [String: Any],
           let content = message["content"] {
            let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private func extractAnthropicAssistantText(from dictionary: [String: Any]) -> String? {
        if let content = dictionary["content"] as? [[String: Any]] {
            let merged = content
                .compactMap { part -> String? in
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    guard partType == "text" || partType.isEmpty else { return nil }
                    if let text = part["text"] as? String, !text.isEmpty {
                        return text
                    }
                    if let text = part["content"] as? String, !text.isEmpty {
                        return text
                    }
                    return nil
                }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !merged.isEmpty {
                return merged
            }
        }

        if let message = dictionary["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let merged = content
                .compactMap { part -> String? in
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    guard partType == "text" || partType.isEmpty else { return nil }
                    if let text = part["text"] as? String, !text.isEmpty {
                        return text
                    }
                    if let text = part["content"] as? String, !text.isEmpty {
                        return text
                    }
                    return nil
                }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !merged.isEmpty {
                return merged
            }
        }

        return nil
    }

    private func extractLMStudioOutputText(_ output: [[String: Any]]) -> String? {
        for item in output {
            let type = ((item["type"] as? String) ?? "").lowercased()
            if type == "reasoning" || type == "tool_call" || type == "invalid_tool_call" {
                continue
            }
            if let content = item["content"] {
                let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
            if let text = item["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if let message = item["message"] {
                let text = flattenedText(from: message).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func flattenedText(from value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any] {
            return array.map(flattenedText(from:)).joined()
        }
        if let dictionary = value as? [String: Any] {
            if let text = dictionary["text"] as? String, !text.isEmpty {
                return text
            }
            if let content = dictionary["content"] as? String, !content.isEmpty {
                return content
            }
            return dictionary.values.map(flattenedText(from:)).joined()
        }
        return ""
    }

    // MARK: - URLSession Data Delegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
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

        let chunk = String(decoding: data, as: UTF8.self)
        ssePartialLine += chunk

        if ssePartialLine.utf8.count > maxBufferedSSEBytes {
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

        let lines = ssePartialLine.split(
            maxSplits: Int.max,
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        )

        var processCount = lines.count
        if let last = ssePartialLine.last, last != "\n" && last != "\r" {
            processCount -= 1
        }

        for i in 0..<max(0, processCount) {
            guard !isCancelled else { return }
            let line = String(lines[i]).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                ssePendingEventType = nil
                continue
            }
            if line.hasPrefix("event:") {
                let eventType = String(line.dropFirst("event:".count))
                    .trimmingCharacters(in: .whitespaces)
                ssePendingEventType = eventType.isEmpty ? nil : eventType
                continue
            }
            guard line.hasPrefix("data:") else { continue }

            let payloadString = String(line.dropFirst("data:".count))
                .trimmingCharacters(in: CharacterSet.whitespaces)

            if payloadString == "[DONE]" {
                ssePendingEventType = nil
                if self.newFormatActive && self.sentThinkOpen && !self.sentThinkClose && !self.isLegacyThinkStream {
                    self.emitDelta(thinkCloseLine)
                    self.sentThinkClose = true
                }
                if self.sawAnyAssistantToken {
                    emitStreamFinishedOnce()
                    stopWatchdog()
                }
                return
            }

            guard let jsonData = payloadString.data(using: String.Encoding.utf8) else { continue }
            let activeStyle = activeEndpointCandidate?.style ?? .openAIChatCompletions

            switch activeStyle {
            case .openAIChatCompletions:
                if let decoded = try? decoder.decode(ChatCompletionChunk.self, from: jsonData),
                   decoded.choices != nil || decoded.usage != nil || decoded.id != nil || decoded.timings != nil {
                    ssePendingEventType = nil
                    self.handleDecodedChunk(decoded)
                }

            case .anthropicMessages:
                if let anthropicEvent = try? decoder.decode(AnthropicStreamEvent.self, from: jsonData),
                   anthropicEvent.type != nil {
                    ssePendingEventType = nil
                    self.handleAnthropicStreamEvent(anthropicEvent)
                }

            case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
                if let lmStudioEvent = try? decoder.decode(LMStudioChatStreamEvent.self, from: jsonData) {
                    self.handleLMStudioStreamEvent(lmStudioEvent, fallbackType: ssePendingEventType)
                    ssePendingEventType = nil
                }
            }
        }

        if processCount >= 0 {
            let remainder = lines.suffix(from: max(0, processCount)).joined(separator: "\n")
            ssePartialLine = remainder
        }
    }

    private func handleDecodedChunk(_ chunk: ChatCompletionChunk) {
        guard !isCancelled else { return }
        var metadata = ChatResponseMetadata.empty
        if let responseID = chunk.id,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.providerResponseID = responseID
        }
        if let usage = chunk.usage {
            metadata.inputTokenCount = usage.prompt_tokens
            metadata.outputTokenCount = usage.completion_tokens
            metadata.reasoningOutputTokenCount = usage.completion_tokens_details?.reasoning_tokens
        }
        if let timings = chunk.timings {
            if metadata.inputTokenCount == nil {
                let promptN = timings.prompt_n ?? 0
                let cacheN = timings.cache_n ?? 0
                let totalPrompt = promptN + cacheN
                if totalPrompt > 0 {
                    metadata.inputTokenCount = totalPrompt
                }
            }
            if metadata.outputTokenCount == nil, let predictedN = timings.predicted_n {
                metadata.outputTokenCount = predictedN
            }
            if metadata.tokensPerSecond == nil, let predictedPerSecond = timings.predicted_per_second {
                metadata.tokensPerSecond = predictedPerSecond
            }
        }

        for choice in chunk.choices ?? [] {
            guard !isCancelled else { return }
            if metadata.finishReason == nil,
               let finishReason = choice.finish_reason,
               !finishReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = finishReason
            }
            guard let delta = choice.delta else { continue }

            let deltaText = delta.content ?? ""

            if deltaText.contains("<think>") || deltaText.contains("</think>") {
                isLegacyThinkStream = true
            }

            if let r = delta.reasoning?.text, !r.isEmpty {
                newFormatActive = true
                if !isLegacyThinkStream && !sentThinkOpen {
                    emitDelta(thinkOpenLine)
                    sentThinkOpen = true
                }
                emitDelta(r)
            }

            if !deltaText.isEmpty {
                if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                    emitDelta(thinkCloseLine)
                    sentThinkClose = true
                }
                emitDelta(deltaText)
            }
        }

        if metadata.hasAnyValue {
            mergeResponseMetadata(metadata)
        }
    }

    private func handleAnthropicStreamEvent(_ event: AnthropicStreamEvent) {
        guard !isCancelled else { return }
        guard let rawType = event.type?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty else {
            return
        }

        var metadata = ChatResponseMetadata.empty
        if let responseID = event.message?.id,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.providerResponseID = responseID
        }
        let usage = event.usage ?? event.message?.usage
        if let usage {
            metadata.inputTokenCount = usage.input_tokens
            metadata.outputTokenCount = usage.output_tokens
        }
        if let stopReason = event.delta?.stop_reason ?? event.message?.stop_reason,
           !stopReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.finishReason = stopReason
        }
        if metadata.hasAnyValue {
            mergeResponseMetadata(metadata)
        }

        switch rawType.lowercased() {
        case "content_block_start":
            let blockType = (event.content_block?.type ?? "").lowercased()
            if blockType.contains("thinking") {
                if !sentThinkOpen {
                    emitDelta(thinkOpenLine)
                    sentThinkOpen = true
                }
                anthropicThinkingActive = true
                if let thinking = event.content_block?.thinking, !thinking.isEmpty {
                    emitDelta(thinking)
                }
            } else if blockType == "text" {
                if anthropicThinkingActive && sentThinkOpen && !sentThinkClose {
                    emitDelta(thinkCloseLine)
                    sentThinkClose = true
                    anthropicThinkingActive = false
                }
                if let text = event.content_block?.text, !text.isEmpty {
                    emitDelta(text)
                }
            }

        case "content_block_delta":
            let deltaType = (event.delta?.type ?? "").lowercased()
            if deltaType.contains("thinking") {
                if !sentThinkOpen {
                    emitDelta(thinkOpenLine)
                    sentThinkOpen = true
                }
                anthropicThinkingActive = true
                let thinking = event.delta?.thinking ?? event.delta?.text ?? ""
                if !thinking.isEmpty {
                    emitDelta(thinking)
                }
            } else {
                if anthropicThinkingActive && sentThinkOpen && !sentThinkClose {
                    emitDelta(thinkCloseLine)
                    sentThinkClose = true
                    anthropicThinkingActive = false
                }
                if let text = event.delta?.text, !text.isEmpty {
                    emitDelta(text)
                }
            }

        case "content_block_stop":
            if anthropicThinkingActive && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine)
                sentThinkClose = true
                anthropicThinkingActive = false
            }

        case "message_stop":
            if anthropicThinkingActive && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine)
                sentThinkClose = true
                anthropicThinkingActive = false
            }
            emitStreamFinishedOnce()
            stopWatchdog()

        case "error":
            let message = event.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = (message?.isEmpty == false) ? message! : NSLocalizedString(
                "Anthropic API error",
                comment: "Fallback error shown when Anthropic stream returns an error event without a message"
            )
            isCancelled = true
            dataTask?.cancel()
            dataTask = nil
            stopConnectionWatchdog()
            stopWatchdog()
            clearActiveEndpointCandidate()
            Task { @MainActor in
                self.onError?(ChatNetworkError.serverError(statusCode: nil, message: resolved))
            }

        default:
            break
        }
    }

    private func handleLMStudioStreamEvent(_ event: LMStudioChatStreamEvent, fallbackType: String? = nil) {
        guard !isCancelled else { return }
        let resolvedType = event.type ?? fallbackType
        guard let rawType = resolvedType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty else { return }

        var metadata = ChatResponseMetadata.empty
        if let responseID = event.response_id ?? event.result?.response_id ?? event.response?.response_id,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.providerResponseID = responseID
        }
        if let stats = event.stats ?? event.result?.stats ?? event.response?.stats {
            metadata.inputTokenCount = normalizedTokenCount(stats.input_tokens)
            metadata.outputTokenCount = normalizedTokenCount(stats.total_output_tokens)
            metadata.reasoningOutputTokenCount = normalizedTokenCount(stats.reasoning_output_tokens)
            metadata.tokensPerSecond = stats.tokens_per_second
            metadata.timeToFirstTokenSeconds = stats.time_to_first_token_seconds
        }
        if metadata.hasAnyValue {
            mergeResponseMetadata(metadata)
        }

        switch rawType.lowercased() {
        case "reasoning.start":
            newFormatActive = true
            if !isLegacyThinkStream && !sentThinkOpen {
                emitDelta(thinkOpenLine)
                sentThinkOpen = true
            }

        case "reasoning.delta":
            newFormatActive = true
            if !isLegacyThinkStream && !sentThinkOpen {
                emitDelta(thinkOpenLine)
                sentThinkOpen = true
            }
            if let content = event.content, !content.isEmpty {
                emitDelta(content)
            }

        case "reasoning.end":
            if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine)
                sentThinkClose = true
            }

        case "message.delta", "response.output_text.delta", "response.content":
            if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine)
                sentThinkClose = true
            }
            let chunk = [
                event.content,
                event.delta,
                event.text,
                event.output_text,
                event.response?.output_text,
                event.response?.text,
                event.response?.content
            ]
                .compactMap { $0 }
                // Preserve whitespace-only deltas (for example a standalone " " token),
                // otherwise streamed output can lose spacing between words.
                .first(where: { !$0.isEmpty })
            if let chunk {
                emitDelta(chunk)
            }

        case "chat.end", "response.completed":
            if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine)
                sentThinkClose = true
            }
            if !sawAnyAssistantToken {
                let fullText = [
                    event.result?.primaryMessageText,
                    event.response?.primaryMessageText,
                    event.output_text,
                    event.content,
                    event.text,
                    event.delta
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty }) ?? ""
                if !fullText.isEmpty {
                    emitDelta(fullText)
                }
            }
            if !sawAnyAssistantToken {
                if let pendingLMStudioStreamErrorMessage,
                   !pendingLMStudioStreamErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isCancelled = true
                    dataTask?.cancel()
                    dataTask = nil
                    stopConnectionWatchdog()
                    clearActiveEndpointCandidate()
                    Task { @MainActor in
                        self.onError?(ChatNetworkError.serverError(statusCode: httpStatusCode, message: pendingLMStudioStreamErrorMessage))
                    }
                }
                stopWatchdog()
                return
            }
            emitStreamFinishedOnce()
            stopWatchdog()

        case "chat.error", "error":
            let message = event.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                pendingLMStudioStreamErrorMessage = message
            }

        default:
            break
        }
    }

    private func emitDelta(_ piece: String) {
        guard !isCancelled else { return }
        lastDeltaAt = Date()
        Task { @MainActor in self.onDelta?(piece) }
        sawAnyAssistantToken = true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let currentTask = self.dataTask, task === currentTask else { return }
        stopConnectionWatchdog()
        stopWatchdog()
        dataTask = nil

        if isCancelled {
            return
        }
        if let status = httpStatusCode, !(200...299).contains(status) {
            let preview = String(data: errorResponseData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message: String
            if preview.isEmpty {
                message = "HTTP \(status)"
            } else {
                let snippet = preview.prefix(400)
                message = "HTTP \(status): \(snippet)"
            }
            clearActiveEndpointCandidate()
            Task { @MainActor in self.onError?(ChatNetworkError.serverError(statusCode: status, message: message)) }
            return
        }

        if let nsError = error as NSError?,
           nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return
        }

        if let error = error {
            clearActiveEndpointCandidate()
            Task { @MainActor in self.onError?(error) }
            return
        }

        if !sawAnyAssistantToken {
            let activeStyle = activeEndpointCandidate?.style ?? .openAIChatCompletions
            let parsedBufferedResponse = parseBufferedSuccessResponse(successResponseData, style: activeStyle)
            if parsedBufferedResponse.metadata.hasAnyValue {
                mergeResponseMetadata(parsedBufferedResponse.metadata)
            }
            if let recoveredText = parsedBufferedResponse.text,
               !recoveredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emitDelta(recoveredText)
                emitStreamFinishedOnce()
                return
            }
            if let recoveredError = parsedBufferedResponse.errorMessage,
               !recoveredError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearActiveEndpointCandidate()
                Task { @MainActor in
                    self.onError?(ChatNetworkError.serverError(statusCode: httpStatusCode, message: recoveredError))
                }
                return
            }
            if let pendingLMStudioStreamErrorMessage,
               !pendingLMStudioStreamErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearActiveEndpointCandidate()
                Task { @MainActor in
                    self.onError?(ChatNetworkError.serverError(statusCode: httpStatusCode, message: pendingLMStudioStreamErrorMessage))
                }
                return
            }
            clearActiveEndpointCandidate()
            Task { @MainActor in self.onError?(ChatNetworkError.emptyResponse) }
            return
        }

        emitStreamFinishedOnce()
    }

// MARK: - Watchdog (reports errors after long waits)

    private func startWatchdog() {
        stopWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard !self.isCancelled else { return }
            let now = Date()

            if let start = self.streamStartAt, self.lastDeltaAt == nil {
                if now.timeIntervalSince(start) > self.firstTokenTimeout {
                    self.dataTask?.cancel()
                    self.dataTask = nil
                    self.stopConnectionWatchdog()
                    self.stopWatchdog()
                    Task { @MainActor in
                        self.onError?(ChatNetworkError.timeout(NSLocalizedString("Connection timed out", comment: "Shown when the chat server request exceeds the timeout")))
                    }
                }
                return
            }

            if let last = self.lastDeltaAt {
                if now.timeIntervalSince(last) > self.silentGapTimeout {
                    self.dataTask?.cancel()
                    self.dataTask = nil
                    self.stopConnectionWatchdog()
                    self.stopWatchdog()
                    Task { @MainActor in
                        self.onError?(ChatNetworkError.timeout(NSLocalizedString("Connection timed out", comment: "Shown when the chat server request exceeds the timeout")))
                    }
                }
            }
        }
        watchdog = timer
        timer.resume()
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func startConnectionWatchdog() {
        stopConnectionWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + connectTimeout, repeating: .never, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard !self.isCancelled else { return }
            guard let task = self.dataTask else { return }
            guard !self.didEstablishConnection else {
                self.stopConnectionWatchdog()
                return
            }
            if task.countOfBytesSent > 0 {
                self.markConnectionEstablishedIfNeeded()
                return
            }
            task.cancel()
            self.dataTask = nil
            self.stopWatchdog()
            self.stopConnectionWatchdog()
            Task { @MainActor in
                self.onError?(ChatNetworkError.timeout(NSLocalizedString("Connection timed out", comment: "Shown when connecting to the chat server takes too long")))
            }
        }
        connectionWatchdog = timer
        timer.resume()
    }

    private func stopConnectionWatchdog() {
        connectionWatchdog?.cancel()
        connectionWatchdog = nil
    }

    private func markConnectionEstablishedIfNeeded() {
        guard !didEstablishConnection else { return }
        didEstablishConnection = true
        stopConnectionWatchdog()
    }

    private func emitStreamFinishedOnce() {
        guard !streamFinishedEmitted else { return }
        streamFinishedEmitted = true
        clearActiveEndpointCandidate()
        Task { @MainActor in self.onStreamFinished?() }
    }
}

// MARK: - Protocol Conformance

extension ChatService: ChatStreamingService {}
