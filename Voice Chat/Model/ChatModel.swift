//
//  ChatModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import Foundation

// === Streaming chunk models ===

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
/// - 可能是 String
/// - 或对象 { content: "…", text: "…" }
/// - 或数组 [ { content/text: "…" }, ... ]
struct ReasoningValue: Codable {
    let text: String

    init(from decoder: Decoder) throws {
        // 1) 直接尝试 String
        if let single = try? String(from: decoder) {
            self.text = single
            return
        }

        // 2) 尝试对象 { content / text }
        if let obj = try? AnyDict(from: decoder) {
            if let s = obj.dict["content"]?.stringValue ?? obj.dict["text"]?.stringValue {
                self.text = s
                return
            }
            // 兜底：把可读字段拼起来
            let joined = obj.dict.values.compactMap { $0.stringValue }.joined()
            if !joined.isEmpty {
                self.text = joined
                return
            }
        }

        // 3) 尝试数组 [ { content/text: "…" }, ... ]
        if let arr = try? [AnyDict](from: decoder) {
            let collected = arr.compactMap { item in
                item.dict["content"]?.stringValue ?? item.dict["text"]?.stringValue
            }.joined()
            self.text = collected
            return
        }

        // 4) 解不出来就置空
        self.text = ""
    }
}

// 轻量 AnyDecodable（仅为读取 string/int/bool 的简单需要）
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

/// 不污染标准库：用于把任意对象解成 [String: AnyDecodable]
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
    var reasoning: ReasoningValue?   // ✅ 新增：兼容 LM Studio 新格式的推理流
}

enum ChatNetworkError: Error {
    case invalidURL
    case serverError(String)
}

// 采用 final + @unchecked Sendable，解决并发要求与可变成员共存的问题
final class ChatService: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    var onMessageReceived: ((ChatMessage) -> Void)?
    var onError: ((Error) -> Void)?

    // ===== 推理/正文缓冲（用于新格式自动注入 <think> 标签） =====
    private var isLegacyThinkStream = false   // 旧格式：内容里自带 <think>
    private var sawAnyAssistantToken = false  // 是否已经输出过任何 assistant token
    private var newFormatActive = false       // 是否检测到新格式 reasoning 流
    private var sentThinkOpen = false         // 是否送出了 "<think>"
    private var sentThinkClose = false        // 是否送出了 "</think>"

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func fetchStreamedData(messages: [ChatMessage]) {
        dataTask?.cancel()

        // 重置新一轮流状态
        resetStreamState()

        // ⚠️ 这里需要访问 MainActor 隔离的 SettingsManager.shared
        // 在主线程上获取必要的只读配置，然后再启动网络请求
        Task { @MainActor in
            let settings = SettingsManager.shared
            let base = settings.chatSettings.apiURL
            let model = settings.chatSettings.selectedModel
            let apiURLString = "\(base)/v1/chat/completions"

            // 把只读值捕获后，回到后台继续发起网络请求
            await self.startStreaming(apiURLString: apiURLString, model: model, messages: messages)
        }
    }

    // 单独拆出启动网络的步骤；不需要是 async，但为了从上层 await 调用，这里标记 async 空挂起点
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
        return messages.map { message in
            [
                "role": message.isUser ? "user" : "assistant",
                "content": message.content
            ]
        }
    }

    // MARK: - URLSession Data Delegate (Streaming)
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        text.enumerateLines { (line, _) in
            guard line.starts(with: "data: ") else { return }
            let jsonPart = line.dropFirst("data: ".count)

            // 流结束
            if jsonPart == "[DONE]" {
                // 新格式：若已打开 <think> 未闭合，自动补 </think>
                if self.newFormatActive && self.sentThinkOpen && !self.sentThinkClose && !self.isLegacyThinkStream {
                    self.emitAssistantDelta("</think>")
                    self.sentThinkClose = true
                }
                return
            }

            guard let data = jsonPart.data(using: .utf8) else { return }

            // 解析 chunk
            if let decoded = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) {
                self.handleDecodedChunk(decoded)
            } else {
                // 无法解码就忽略该行，避免中断
            }
        }
    }

    private func handleDecodedChunk(_ chunk: ChatCompletionChunk) {
        guard let choices = chunk.choices else { return }

        for choice in choices {
            guard let delta = choice.delta else { continue }

            let deltaText = delta.content ?? ""

            // ===== 1) 检测旧格式：内容里直接出现 <think> 或 </think> =====
            if deltaText.contains("<think>") || deltaText.contains("</think>") {
                isLegacyThinkStream = true
            }

            // ===== 2) 处理新格式 reasoning 流 =====
            if let r = delta.reasoning?.text, !r.isEmpty {
                newFormatActive = true

                // 如果不是旧格式，且还没发过 <think>，先发一次 "<think>"
                if !isLegacyThinkStream && !sentThinkOpen {
                    emitAssistantDelta("<think>")
                    sentThinkOpen = true
                }
                // 发 reasoning token
                emitAssistantDelta(r)
            }

            // ===== 3) 处理正文 content 流 =====
            if !deltaText.isEmpty {
                if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                    // 新格式下，第一次正文到来时，先闭合 </think>
                    emitAssistantDelta("</think>")
                    sentThinkClose = true
                }

                emitAssistantDelta(deltaText)
            }
        }
    }

    /// 发出一段 assistant 的增量文本；你的 ChatViewModel 会把碎片拼接为同一条 assistant 消息
    private func emitAssistantDelta(_ piece: String) {
        let message = ChatMessage(content: piece, isUser: false)
        DispatchQueue.main.async { [weak self] in
            self?.onMessageReceived?(message)
        }
        sawAnyAssistantToken = true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.onError?(error)
            }
        }
    }
}

// MARK: - Sendable Conformance
extension ChatMessage: @unchecked Sendable {}
