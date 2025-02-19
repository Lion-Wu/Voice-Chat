//
//  ChatViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/18.
//

import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var userMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var chatSession: ChatSession

    private var chatService = ChatService()
    private var settingsManager = SettingsManager.shared
    var onUpdate: (() -> Void)?

    init(chatSession: ChatSession) {
        self.chatSession = chatSession

        // Since we are on the main actor, assigning these closures is allowed.
        chatService.onMessageReceived = { [weak self] message in
            guard let self = self else { return }
            self.handleReceivedMessage(message)
        }

        chatService.onError = { [weak self] error in
            guard let self = self else { return }
            self.isLoading = false
            print("Chat error: \(error.localizedDescription)")
        }
    }

    func sendMessage() {
        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        let userMsg = ChatMessage(content: trimmedMessage, isUser: true)
        chatSession.messages.append(userMsg)
        if chatSession.title == "New Chat" {
            chatSession.title = trimmedMessage
        }
        isLoading = true
        userMessage = ""
        onUpdate?()

        // Capture current messages on the main actor
        let currentMessages = chatSession.messages
        // Perform network call on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            self.chatService.fetchStreamedData(messages: currentMessages)
        }
    }

    private func handleReceivedMessage(_ message: ChatMessage) {
        if let lastMessage = chatSession.messages.last, !lastMessage.isUser && lastMessage.isActive {
            lastMessage.content += message.content
        } else {
            chatSession.messages.append(message)
        }
        isLoading = false
        onUpdate?()
    }
}
