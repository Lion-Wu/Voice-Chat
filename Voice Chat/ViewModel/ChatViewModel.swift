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
        Task {
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

    /// 对“系统消息”执行重新生成逻辑：
    /// 1. 从指定消息开始到会话末尾的所有消息都删除
    /// 2. 根据删除后的会话，再次向服务器请求生成新的回复
    func regenerateSystemMessage(_ message: ChatMessage) {
        guard let index = chatSession.messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        // 删除从这条系统消息到末尾的所有消息
        chatSession.messages.removeSubrange(index...)
        onUpdate?()

        // 重新请求回复
        let currentMessages = chatSession.messages
        isLoading = true
        Task {
            self.chatService.fetchStreamedData(messages: currentMessages)
        }
    }

    /// 对“用户消息”执行编辑逻辑：
    /// 1. 从指定用户消息开始到会话末尾的所有消息都删除
    /// 2. 把该用户消息的内容放到输入框里，允许用户修改后再次点击发送
    func editUserMessage(_ message: ChatMessage) {
        guard let index = chatSession.messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        // 删除从这条用户消息到末尾的所有消息
        chatSession.messages.removeSubrange(index...)
        // 将原内容放入输入框，等待用户编辑并发送
        userMessage = message.content
        onUpdate?()
    }
}
