//
//  ChatViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/18.
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
                self?.handleReceivedMessage(message)
            }
        }

        chatService.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                // Handle error appropriately
            }
        }
    }

    func sendMessage() {
        guard !userMessage.isEmpty else { return }
        let userMsg = ChatMessage(content: userMessage, isUser: true)
        messages.append(userMsg)
        isLoading = true
        chatService.fetchStreamedData(messages: messages)
        userMessage = ""
    }

    private func handleReceivedMessage(_ message: ChatMessage) {
        if let lastMessage = messages.last, !lastMessage.isUser && lastMessage.isActive {
            messages[messages.count - 1].content += message.content
        } else {
            messages.append(message)
        }
        isLoading = false
    }
}
