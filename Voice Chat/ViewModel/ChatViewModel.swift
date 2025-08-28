//
//  ChatViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/18.
//

import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published State
    @Published var userMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var chatSession: ChatSession

    // MARK: - Dependencies
    private let chatService = ChatService()
    private let settingsManager = SettingsManager.shared

    // 通知外层存储（保存、刷新列表等）
    var onUpdate: (() -> Void)?

    // 防重复发送
    private var sending = false

    // MARK: - Init
    init(chatSession: ChatSession) {
        self.chatSession = chatSession

        chatService.onMessageReceived = { [weak self] message in
            guard let self = self else { return }
            self.handleReceivedMessage(message)
        }
        chatService.onError = { [weak self] error in
            guard let self = self else { return }
            self.isLoading = false
            self.sending = false
            print("Chat error: \(error.localizedDescription)")
        }
        chatService.onStreamFinished = { [weak self] in
            guard let self = self else { return }
            // 将最后一条助手消息标记为完成（不再合并后续流）
            if let last = self.chatSession.messages.last, !last.isUser {
                last.isActive = false
            }
            self.isLoading = false
            self.sending = false
            self.onUpdate?()
        }
    }

    // MARK: - Intent

    func sendMessage() {
        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        guard !sending else { return } // 避免重复点击触发并发请求

        // 1) 追加用户消息
        let userMsg = ChatMessage(content: trimmedMessage, isUser: true)
        chatSession.messages.append(userMsg)
        if chatSession.title == "New Chat" {
            chatSession.title = trimmedMessage
        }

        // 2) UI 状态更新
        isLoading = true
        sending = true
        userMessage = ""
        onUpdate?()

        // 3) 捕获当前消息快照后发起流式请求
        let currentMessages = chatSession.messages
        Task.detached { [chatService] in
            chatService.fetchStreamedData(messages: currentMessages)
        }
    }

    // 合并助手流式片段：持续写入同一条“活跃助手消息”
    private func handleReceivedMessage(_ message: ChatMessage) {
        if let lastMessage = chatSession.messages.last, !lastMessage.isUser && lastMessage.isActive {
            lastMessage.content += message.content
        } else {
            chatSession.messages.append(message)
        }
        isLoading = true
        onUpdate?()
    }

    /// 对“系统消息”执行重新生成逻辑
    func regenerateSystemMessage(_ message: ChatMessage) {
        guard let index = chatSession.messages.firstIndex(where: { $0.id == message.id }) else { return }
        chatSession.messages.removeSubrange(index...)
        onUpdate?()

        let currentMessages = chatSession.messages
        isLoading = true
        sending = true
        Task.detached { [chatService] in
            chatService.fetchStreamedData(messages: currentMessages)
        }
    }

    /// 对“用户消息”执行编辑逻辑
    func editUserMessage(_ message: ChatMessage) {
        guard let index = chatSession.messages.firstIndex(where: { $0.id == message.id }) else { return }
        chatSession.messages.removeSubrange(index...)
        userMessage = message.content
        onUpdate?()
    }
}
