//
//  chatStructure.swift
//  Voice Chat
//
//  Created by 小吴苹果机器人 on 2024/1/8.
//

import Foundation

// Data models
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

// Chat message representation
struct ChatMessage: Identifiable, Equatable {
    var id = UUID()
    var content: String
    var isUser: Bool
    var isActive: Bool = true
}

// ChatService handles chat-related API calls
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

        // Fetch the latest settings
        let settingsManager = SettingsManager.shared
        let apiURLString = "\(settingsManager.chatSettings.apiURL)/v1/chat/completions"
        guard let apiURL = URL(string: apiURLString) else {
            onError?(ChatNetworkError.invalidURL)
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
            onError?(error)
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

    // URLSessionDataDelegate method
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        text.enumerateLines { (line, _) in
            if line.starts(with: "data: ") {
                let jsonPart = line.dropFirst("data: ".count)
                if let data = jsonPart.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) {
                    decoded.choices?.forEach { choice in
                        if let content = choice.delta?.content {
                            DispatchQueue.main.async { [weak self] in
                                let message = ChatMessage(content: content, isUser: false)
                                self?.onMessageReceived?(message)
                            }
                        }
                    }
                }
            }
        }
    }
}

enum ChatNetworkError: Error {
    case invalidURL
    case serverError
}
