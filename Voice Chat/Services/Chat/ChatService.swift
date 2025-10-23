//
//  ChatService.swift
//  Voice Chat
//
//  Created as part of MVVM restructuring.
//

import Foundation

/// Service responsible for handling streamed chat completions.
final class ChatService: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // MARK: - Session Lifecycle
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    /// Main-actor callbacks to keep SwiftData usage safe.
    var onDelta: (@MainActor (String) -> Void)?
    var onError: (@MainActor (Error) -> Void)?
    var onStreamFinished: (@MainActor () -> Void)?

    // MARK: - Streaming State
    private var isLegacyThinkStream = false
    private var sawAnyAssistantToken = false
    private var newFormatActive = false
    private var sentThinkOpen = false
    private var sentThinkClose = false

    private var ssePartialLine: String = ""

    // MARK: - Watchdog
    private let firstTokenTimeout: TimeInterval = 3600
    private let silentGapTimeout: TimeInterval = 3600
    private var streamStartAt: Date?
    private var lastDeltaAt: Date?
    private var watchdog: Timer?

    private var isCancelled: Bool = false

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 3900
        configuration.timeoutIntervalForResource = 3900
        configuration.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    deinit {
        stopWatchdog()
    }

    // MARK: - Public API

    /// Starts a new streaming request for the supplied message history.
    @MainActor
    func fetchStreamedData(messages: [ChatMessage]) {
        dataTask?.cancel()
        resetStreamState()
        isCancelled = false

        let settings = SettingsManager.shared
        let baseURL = settings.chatSettings.apiURL
        let model = settings.chatSettings.selectedModel
        let apiURLString = "\(baseURL)/v1/chat/completions"
        startStreaming(apiURLString: apiURLString, model: model, messages: messages)
    }

    /// Cancels the current streaming request if present.
    func cancelStreaming() {
        isCancelled = true
        dataTask?.cancel()
        dataTask = nil
        stopWatchdog()
        resetStreamState()
    }

    // MARK: - Private Helpers

    private func startStreaming(apiURLString: String, model: String, messages: [ChatMessage]) {
        guard let apiURL = URL(string: apiURLString) else {
            Task { @MainActor in self.onError?(ChatNetworkError.invalidURL) }
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 3900
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("keep-alive", forHTTPHeaderField: "Connection")
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let requestBody: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": transformedMessagesForRequest(messages: messages)
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
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
        ssePartialLine = ""
        streamStartAt = nil
        lastDeltaAt = nil
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

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isCancelled else { return }

        let chunk = String(decoding: data, as: UTF8.self)
        ssePartialLine += chunk

        let lines = ssePartialLine.split(
            maxSplits: Int.max,
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        )

        var processCount = lines.count
        if let last = ssePartialLine.last, last != "\n" && last != "\r" {
            processCount -= 1
        }

        for index in 0..<max(0, processCount) {
            guard !isCancelled else { return }
            let line = String(lines[index]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard line.hasPrefix("data:") else { continue }

            let payloadString = String(line.dropFirst("data:".count))
                .trimmingCharacters(in: CharacterSet.whitespaces)

            if payloadString == "[DONE]" {
                if newFormatActive && sentThinkOpen && !sentThinkClose && !isLegacyThinkStream {
                    emitDelta("</think>")
                    sentThinkClose = true
                }
                Task { @MainActor in self.onStreamFinished?() }
                stopWatchdog()
                return
            }

            guard let jsonData = payloadString.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData) {
                handleDecodedChunk(decoded)
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

            if let reasoning = delta.reasoning?.text, !reasoning.isEmpty {
                newFormatActive = true
                if !isLegacyThinkStream && !sentThinkOpen {
                    emitDelta("<think>")
                    sentThinkOpen = true
                }
                emitDelta(reasoning)
            }

            if !deltaText.isEmpty {
                if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                    emitDelta("</think>")
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
        stopWatchdog()
        if let error {
            Task { @MainActor in self.onError?(error) }
        } else {
            Task { @MainActor in self.onStreamFinished?() }
        }
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        stopWatchdog()
        watchdog = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard !self.isCancelled else { return }
            let now = Date()

            if let start = self.streamStartAt, self.lastDeltaAt == nil {
                if now.timeIntervalSince(start) > self.firstTokenTimeout {
                    self.dataTask?.cancel()
                    self.dataTask = nil
                    self.stopWatchdog()
                    Task { @MainActor in self.onError?(ChatNetworkError.timeout("Request timed out.")) }
                }
                return
            }

            if let last = self.lastDeltaAt {
                if now.timeIntervalSince(last) > self.silentGapTimeout {
                    self.dataTask?.cancel()
                    self.dataTask = nil
                    self.stopWatchdog()
                    Task { @MainActor in self.onError?(ChatNetworkError.timeout("Request timed out.")) }
                }
            }
        }
        if let watchdog {
            watchdog.tolerance = 1.0
            RunLoop.current.add(watchdog, forMode: .common)
        }
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }
}
