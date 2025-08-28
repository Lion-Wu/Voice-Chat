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

/// 兼容 LM Studio v0.3.23+ 的 reasoning 流式字段
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
}

// MARK: - ChatService (Streaming)

final class ChatService: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    var onMessageReceived: ((ChatMessage) -> Void)?
    var onError: ((Error) -> Void)?
    var onStreamFinished: (() -> Void)?

    // 推理/正文状态
    private var isLegacyThinkStream = false
    private var sawAnyAssistantToken = false
    private var newFormatActive = false
    private var sentThinkOpen = false
    private var sentThinkClose = false

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func fetchStreamedData(messages: [ChatMessage]) {
        dataTask?.cancel()
        resetStreamState()

        // 在主线程捕获只读配置后再开请求
        Task { @MainActor in
            let settings = SettingsManager.shared
            let base = settings.chatSettings.apiURL
            let model = settings.chatSettings.selectedModel
            let apiURLString = "\(base)/v1/chat/completions"
            await self.startStreaming(apiURLString: apiURLString, model: model, messages: messages)
        }
    }

    private func startStreaming(apiURLString: String, model: String, messages: [ChatMessage]) async {
        guard let apiURL = URL(string: apiURLString) else {
            DispatchQueue.main.async { self.onError?(ChatNetworkError.invalidURL) }
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"

        let requestBody: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": transformedMessagesForRequest(messages: messages)
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
        } catch {
            DispatchQueue.main.async { self.onError?(error) }
            return
        }

        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }

    private func resetStreamState() {
        isLegacyThinkStream = false
        sawAnyAssistantToken = false
        newFormatActive = false
        sentThinkOpen = false
        sentThinkClose = false
    }

    private func transformedMessagesForRequest(messages: [ChatMessage]) -> [[String: String]] {
        messages.map { message in
            [
                "role": message.isUser ? "user" : "assistant",
                "content": message.content
            ]
        }
    }

    // MARK: - URLSession Data Delegate
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        text.enumerateLines { (line, _) in
            guard line.starts(with: "data: ") else { return }
            let jsonPart = line.dropFirst("data: ".count)

            if jsonPart == "[DONE]" {
                // 新格式：若 <think> 未闭合，自动闭合
                if self.newFormatActive && self.sentThinkOpen && !self.sentThinkClose && !self.isLegacyThinkStream {
                    self.emitAssistantDelta("</think>")
                    self.sentThinkClose = true
                }
                DispatchQueue.main.async { self.onStreamFinished?() }
                return
            }

            guard let data = jsonPart.data(using: .utf8) else { return }

            if let decoded = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) {
                self.handleDecodedChunk(decoded)
            } else {
                // 忽略无法解码的片段
            }
        }
    }

    private func handleDecodedChunk(_ chunk: ChatCompletionChunk) {
        guard let choices = chunk.choices else { return }
        for choice in choices {
            guard let delta = choice.delta else { continue }

            let deltaText = delta.content ?? ""

            // 旧格式：内容自带 <think> / </think>
            if deltaText.contains("<think>") || deltaText.contains("</think>") {
                isLegacyThinkStream = true
            }

            // Handling reasoning stream (new format)
            if let r = delta.reasoning?.text, !r.isEmpty {
                newFormatActive = true
                if !isLegacyThinkStream && !sentThinkOpen {
                    emitAssistantDelta("<think>")
                    sentThinkOpen = true
                }
                emitAssistantDelta(r)
            }

            // Handling content stream
            if !deltaText.isEmpty {
                if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                    emitAssistantDelta("</think>")
                    sentThinkClose = true
                }
                emitAssistantDelta(deltaText)
            }
        }
    }

    private func emitAssistantDelta(_ piece: String) {
        let message = ChatMessage(content: piece, isUser: false)
        DispatchQueue.main.async { [weak self] in
            self?.onMessageReceived?(message)
        }
        sawAnyAssistantToken = true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async { self.onError?(error) }
        } else {
            // 正常结束但未收到 [DONE] 的情况，也触发完成
            DispatchQueue.main.async { self.onStreamFinished?() }
        }
    }
}

// MARK: - Sendable Conformance
extension ChatMessage: @unchecked Sendable {}
