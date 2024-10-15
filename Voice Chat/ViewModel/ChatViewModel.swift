//
//  ChatWithVoiceViewModel.swift
//  Voice Chat
//
//  Created by 小吴苹果机器人 on 2024/1/18.
//

import Foundation

class ChatViewModel: ObservableObject {
    @Published var userMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var messages: [ChatMessage] = []

    private var chatService = ChatService()
    private var settingsManager = SettingsManager.shared

    init() {
        chatService.onMessageReceived = { [weak self] message in
            DispatchQueue.main.async {
                if let lastMessage = self?.messages.last, !lastMessage.isUser && lastMessage.isActive {
                    self?.messages[self!.messages.count - 1].content += message.content
                } else {
                    self?.messages.append(message)
                }
                self?.isLoading = false
            }
        }

        chatService.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                // Handle error
            }
        }
    }

    func sendMessage() {
        let userMsg = ChatMessage(content: userMessage, isUser: true)
        messages.append(userMsg)
        isLoading = true
        chatService.fetchStreamedData(messages: messages)
        userMessage = ""
    }
}
