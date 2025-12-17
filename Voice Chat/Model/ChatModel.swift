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
}

struct Choice: Codable {
    var index: Int?
    var finish_reason: String?
    var delta: Delta?
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

enum ChatNetworkError: Error {
    case invalidURL
    case serverError(String)
    case timeout(String)
}

// MARK: - Configuration

/// Provides chat API configuration without tying the service to a global singleton.
protocol ChatServiceConfiguring {
    var apiBaseURL: String { get }
    var modelIdentifier: String { get }
}

/// Lightweight snapshot of chat configuration to avoid actor-hopping from main-actor singletons.
struct ChatServiceConfiguration: ChatServiceConfiguring, Equatable {
    let apiBaseURL: String
    let modelIdentifier: String
}

// MARK: - Service Contracts

@MainActor
protocol ChatStreamingService: AnyObject {
    var onDelta: (@MainActor (String) -> Void)? { get set }
    var onError: (@MainActor (Error) -> Void)? { get set }
    var onStreamFinished: (@MainActor () -> Void)? { get set }

    func fetchStreamedData(messages: [ChatMessage])
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
    private let maxBufferedSSEBytes = 512 * 1024
    private let thinkOpenLine = "<think>\n"
    private let thinkCloseLine = "\n</think>\n"
    private let decoder = JSONDecoder()

    // Watchdog configuration to cover long-running sessions (up to ~1 hour).
    private let firstTokenTimeout: TimeInterval = 3600        // Wait up to one hour for the first token.
    private let silentGapTimeout: TimeInterval  = 3600        // Allow up to one hour of silence between tokens.
    private var streamStartAt: Date?
    private var lastDeltaAt: Date?
    private var watchdog: DispatchSourceTimer?

    // Cancel flag to ignore any residual deltas after stopping.
    private var isCancelled: Bool = false

    // HTTP status/error accumulation for non-2xx responses.
    private var httpStatusCode: Int?
    private let errorBodyCaptureLimit = 32 * 1024
    private var errorResponseData = Data()

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
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest  = 3900   // Adds a few minutes of headroom beyond one hour.
        configuration.timeoutIntervalForResource = 3900
        configuration.httpMaximumConnectionsPerHost = 1
        self.session = URLSession(configuration: configuration, delegate: delegateProxy, delegateQueue: sessionQueue)
    }

    deinit {
        session?.invalidateAndCancel()
        stopWatchdog()
    }

    /// Called on the main actor to avoid crossing actor boundaries with SwiftData models.
    @MainActor
    func fetchStreamedData(messages: [ChatMessage]) {
        let base = configurationProvider.apiBaseURL
        let model = configurationProvider.modelIdentifier
        guard let apiURLString = buildAPIURLString(base: base) else {
            onError?(ChatNetworkError.invalidURL)
            return
        }

        let payload = transformedMessagesForRequest(messages: messages)
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.dataTask?.cancel()
            self.dataTask = nil
            self.stopWatchdog()
            self.resetStreamState()
            self.isCancelled = false
            self.startStreaming(apiURLString: apiURLString, model: model, messagePayload: payload)
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
        }
    }

    /// Builds the request and starts the URLSession stream (non-async helper).
    private func startStreaming(apiURLString: String, model: String, messagePayload: [[String: String]]) {
        guard let apiURL = URL(string: apiURLString) else {
            Task { @MainActor in self.onError?(ChatNetworkError.invalidURL) }
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 3900 // Individual request timeout with extra buffer beyond one hour.
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("keep-alive", forHTTPHeaderField: "Connection")
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let requestBody: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messagePayload
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
        } catch {
            Task { @MainActor in self.onError?(error) }
            return
        }

        streamStartAt = Date()
        lastDeltaAt = nil
        startWatchdog()

        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }

    private func resetStreamState() {
        isLegacyThinkStream = false
        sawAnyAssistantToken = false
        newFormatActive = false
        sentThinkOpen = false
        sentThinkClose = false
        streamFinishedEmitted = false
        ssePartialLine = ""
        streamStartAt = nil
        lastDeltaAt = nil
        httpStatusCode = nil
        errorResponseData.removeAll(keepingCapacity: true)
    }

    private func transformedMessagesForRequest(messages: [ChatMessage]) -> [[String: String]] {
        messages
            .filter { !$0.content.hasPrefix("!error:") }
            .map { message in
                [
                    "role": message.isUser ? "user" : "assistant",
                    "content": message.content
                ]
            }
    }

    private func buildAPIURLString(base: String) -> String? {
        var sanitized = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }

        if !sanitized.contains("://") {
            sanitized = "http://\(sanitized)"
        }
        while sanitized.hasSuffix("/") { sanitized.removeLast() }

        guard var comps = URLComponents(string: sanitized) else { return nil }
        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }

        if path.hasSuffix("/v1/chat/completions") {
            // Keep as-is.
        } else if path.hasSuffix("/v1/chat") {
            comps.path = path + "/completions"
        } else if path.hasSuffix("/v1") {
            comps.path = path + "/chat/completions"
        } else {
            comps.path = path + "/v1/chat/completions"
        }

        return comps.url?.absoluteString
    }

    // MARK: - URLSession Data Delegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let currentTask = self.dataTask, dataTask === currentTask else {
            completionHandler(.cancel)
            return
        }
        if let http = response as? HTTPURLResponse {
            httpStatusCode = http.statusCode
            if !(200...299).contains(http.statusCode) {
                errorResponseData.removeAll(keepingCapacity: true)
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let currentTask = self.dataTask, dataTask === currentTask else { return }
        guard !isCancelled else { return }

        if let status = httpStatusCode, !(200...299).contains(status) {
            if errorResponseData.count < errorBodyCaptureLimit {
                let remaining = errorBodyCaptureLimit - errorResponseData.count
                errorResponseData.append(data.prefix(remaining))
            }
            return
        }

        let chunk = String(decoding: data, as: UTF8.self)
        ssePartialLine += chunk

        if ssePartialLine.utf8.count > maxBufferedSSEBytes {
            isCancelled = true
            dataTask.cancel()
            stopWatchdog()
            Task { @MainActor in
                self.onError?(ChatNetworkError.serverError("Stream payload exceeded safety limit"))
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
            guard !line.isEmpty else { continue }
            guard line.hasPrefix("data:") else { continue }

            let payloadString = String(line.dropFirst("data:".count))
                .trimmingCharacters(in: CharacterSet.whitespaces)

            if payloadString == "[DONE]" {
                if self.newFormatActive && self.sentThinkOpen && !self.sentThinkClose && !self.isLegacyThinkStream {
                    self.emitDelta(thinkCloseLine)
                    self.sentThinkClose = true
                }
                emitStreamFinishedOnce()
                stopWatchdog()
                return
            }

            guard let jsonData = payloadString.data(using: String.Encoding.utf8) else { continue }
            if let decoded = try? decoder.decode(ChatCompletionChunk.self, from: jsonData) {
                self.handleDecodedChunk(decoded)
            }
        }

        if processCount >= 0 {
            let remainder = lines.suffix(from: max(0, processCount)).joined(separator: "\n")
            ssePartialLine = remainder
        }
    }

    private func handleDecodedChunk(_ chunk: ChatCompletionChunk) {
        guard !isCancelled else { return }
        guard let choices = chunk.choices else { return }
        for choice in choices {
            guard !isCancelled else { return }
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
    }

    private func emitDelta(_ piece: String) {
        guard !isCancelled else { return }
        lastDeltaAt = Date()
        Task { @MainActor in self.onDelta?(piece) }
        sawAnyAssistantToken = true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let currentTask = self.dataTask, task === currentTask else { return }
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
            Task { @MainActor in self.onError?(ChatNetworkError.serverError(message)) }
            return
        }

        if let nsError = error as NSError?,
           nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return
        }

        if let error = error {
            Task { @MainActor in self.onError?(error) }
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
                    self.stopWatchdog()
                    Task { @MainActor in self.onError?(ChatNetworkError.timeout("Connection timed out")) }
                }
                return
            }

            if let last = self.lastDeltaAt {
                if now.timeIntervalSince(last) > self.silentGapTimeout {
                    self.dataTask?.cancel()
                    self.dataTask = nil
                    self.stopWatchdog()
                    Task { @MainActor in self.onError?(ChatNetworkError.timeout("Connection timed out")) }
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

    private func emitStreamFinishedOnce() {
        guard !streamFinishedEmitted else { return }
        streamFinishedEmitted = true
        Task { @MainActor in self.onStreamFinished?() }
    }
}

// MARK: - Protocol Conformance

extension ChatService: ChatStreamingService {}
