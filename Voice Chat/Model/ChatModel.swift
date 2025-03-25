//
//  ChatModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import Foundation

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

struct Delta: Codable {
    var role: String?
    var content: String?
}

enum ChatNetworkError: Error {
    case invalidURL
    case serverError(String)
}

@MainActor
class ChatService: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    var onMessageReceived: ((ChatMessage) -> Void)?
    var onError: ((Error) -> Void)?

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func fetchStreamedData(messages: [ChatMessage]) {
        dataTask?.cancel()

        let settingsManager = SettingsManager.shared
        let apiURLString = "\(settingsManager.chatSettings.apiURL)/v1/chat/completions"
        guard let apiURL = URL(string: apiURLString) else {
            DispatchQueue.main.async {
                self.onError?(ChatNetworkError.invalidURL)
            }
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"

        let requestBody: [String: Any] = [
            "model": settingsManager.chatSettings.selectedModel,
            "stream": true,
            "messages": transformedMessagesForRequest(messages: messages)
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
        } catch {
            DispatchQueue.main.async {
                self.onError?(error)
            }
            return
        }

        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }

    private func transformedMessagesForRequest(messages: [ChatMessage]) -> [[String: String]] {
        return messages.map { message in
            [
                "role": message.isUser ? "user" : "assistant",
                "content": message.content
            ]
        }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        text.enumerateLines { (line, _) in
            guard line.starts(with: "data: ") else { return }
            let jsonPart = line.dropFirst("data: ".count)
            if jsonPart == "[DONE]" {
                // The stream ended successfully
                return
            }
            if let data = jsonPart.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) {
                decoded.choices?.forEach { choice in
                    if let content = choice.delta?.content {
                        let message = ChatMessage(content: content, isUser: false)
                        DispatchQueue.main.async { [weak self] in
                            self?.onMessageReceived?(message)
                        }
                    }
                }
            } else {
                // Unable to decode this particular chunk. It's safer to ignore rather than fail.
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.onError?(error)
            }
        }
    }
}

// MARK: - Sendable Conformance
extension ChatMessage: @unchecked Sendable {}
