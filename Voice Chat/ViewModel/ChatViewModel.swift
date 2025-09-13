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
    /// 整个请求生命周期内为 true（用于“停止”按钮）
    @Published var isLoading: Bool = false
    /// 仅在“首个令牌/字符到达之前”为 true（用于首屏三个点 Loading）
    @Published var isPriming: Bool = false
    @Published var chatSession: ChatSession

    /// 编辑模式：为 nil 表示未在编辑；非 nil 表示正在编辑以该消息为分界，后续消息仅“视觉隐藏”
    @Published var editingBaseMessageID: UUID? = nil
    var isEditing: Bool { editingBaseMessageID != nil }

    // MARK: - Dependencies
    private let chatService = ChatService()
    private let settingsManager = SettingsManager.shared

    // 通知外层存储（保存、刷新列表等）
    var onUpdate: (() -> Void)?

    // 防重复发送
    private var sending = false

    // 当前流式回复对应的助手消息（合并增量）
    private var currentAssistantMessageID: UUID?
    /// 最近一次因错误而“被中断”的助手消息，用于“重试”时删除
    private var interruptedAssistantMessageID: UUID?

    // MARK: - Init
    init(chatSession: ChatSession) {
        self.chatSession = chatSession

        // ★ 增量字符串回调（显式回到主线程）
        chatService.onDelta = { [weak self] piece in
            guard let self = self else { return }
            self.handleAssistantDelta(piece)
        }
        chatService.onError = { [weak self] error in
            guard let self = self else { return }
            // 出错也视为结束
            self.isPriming = false
            self.isLoading = false
            self.sending = false

            // 将当前活跃助手消息标记结束，并记录为“被中断”的那一条
            if let id = self.currentAssistantMessageID,
               let last = self.chatSession.messages.first(where: { $0.id == id }) {
                last.isActive = false
                self.interruptedAssistantMessageID = id
            } else {
                self.interruptedAssistantMessageID = nil
            }
            self.currentAssistantMessageID = nil

            // 在对话中插入“错误气泡”
            let err = ChatMessage(
                content: "!error:\(error.localizedDescription)",
                isUser: false,
                isActive: false,
                createdAt: Date(),
                session: self.chatSession
            )
            self.chatSession.messages.append(err)
            self.onUpdate?()
        }
        chatService.onStreamFinished = { [weak self] in
            guard let self = self else { return }
            if let id = self.currentAssistantMessageID,
               let last = self.chatSession.messages.first(where: { $0.id == id }) {
                last.isActive = false
            }
            self.isPriming = false
            self.isLoading = false
            self.sending = false
            self.currentAssistantMessageID = nil
            self.interruptedAssistantMessageID = nil
            self.onUpdate?() // 结束时再保存一次
        }
    }

    // MARK: - Helpers (stable ordering & safe trimming)

    /// 始终按时间升序提供上下文，避免“数组内部顺序”和“展示顺序”不一致
    private func chronologicalMessages() -> [ChatMessage] {
        chatSession.messages.sorted { $0.createdAt < $1.createdAt }
    }

    /// 按 createdAt 做分界删除，inclusive = 是否包含分界本身
    private func trimMessages(from cutoff: Date, inclusive: Bool) {
        if inclusive {
            chatSession.messages.removeAll { $0.createdAt >= cutoff }
        } else {
            chatSession.messages.removeAll { $0.createdAt > cutoff }
        }
    }

    /// 若有进行中的助手消息，先标记为结束
    private func closeActiveAssistantMessageIfAny() {
        if let id = currentAssistantMessageID,
           let msg = chatSession.messages.first(where: { $0.id == id }) {
            msg.isActive = false
        }
        currentAssistantMessageID = nil
    }

    // MARK: - Intent

    func sendMessage() {
        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        guard !sending else { return } // 避免重复点击触发并发请求

        // 如果正在编辑：此时仅“视觉隐藏”了尾部，真正发送前再一次性删除尾部
        if let baseID = editingBaseMessageID,
           let base = chatSession.messages.first(where: { $0.id == baseID }) {
            // 包含分界（编辑就是要替换分界这条用户消息）
            trimMessages(from: base.createdAt, inclusive: true)
            editingBaseMessageID = nil
        }

        // 1) 追加用户消息
        let userMsg = ChatMessage(content: trimmedMessage, isUser: true, isActive: true, createdAt: Date(), session: chatSession)
        chatSession.messages.append(userMsg)
        if chatSession.title == "New Chat" {
            chatSession.title = trimmedMessage
        }

        // 2) UI 状态更新
        isPriming = true                // 只在首 token 到达前显示“加载中”三个点
        isLoading = true                // 整个生成阶段显示“停止”按钮
        sending = true
        closeActiveAssistantMessageIfAny()
        interruptedAssistantMessageID = nil
        userMessage = ""
        onUpdate?()

        // 3) 捕获当前消息快照（时间升序）并发起流式请求（主线程/主 actor 调用）
        let currentMessages = chronologicalMessages()
        chatService.fetchStreamedData(messages: currentMessages)
    }

    /// 用户点击“停止”时调用
    func cancelCurrentRequest() {
        guard sending || isLoading || isPriming else { return }
        chatService.cancelStreaming()
        // 主动结束 UI 状态
        closeActiveAssistantMessageIfAny()
        isPriming = false
        isLoading = false
        sending = false
        // 注意：手动停止不视为“错误”，不记录 interruptedAssistantMessageID
        onUpdate?()
    }

    // ★ 合并助手流式片段：所有增量写入同一条“活跃助手消息”
    private func handleAssistantDelta(_ piece: String) {
        // 若已不处于“生成中”状态（包括已停止/错误后），丢弃任何残余增量，避免新建额外系统消息
        guard isPriming || isLoading || sending else { return }

        // 首个令牌到达，隐藏“加载中”三个点
        if isPriming { isPriming = false }

        if let id = currentAssistantMessageID,
           let msg = chatSession.messages.first(where: { $0.id == id }) {
            // 已有活跃助手消息 -> 直接追加
            msg.content += piece
        } else {
            // 没有则新建一条助手消息并记录 ID
            let sys = ChatMessage(content: piece, isUser: false, isActive: true, createdAt: Date(), session: chatSession)
            chatSession.messages.append(sys)
            currentAssistantMessageID = sys.id
        }

        // 仍处于整体加载阶段（用于“停止”按钮）
        isLoading = true
        onUpdate?()
    }

    /// 重新生成：从某条系统消息开始删除后续并重新请求（删除分界本身 + 其后）
    func regenerateSystemMessage(_ message: ChatMessage) {
        guard !sending else { return }
        chatService.cancelStreaming()
        closeActiveAssistantMessageIfAny()
        interruptedAssistantMessageID = nil

        guard !message.isUser else { return } // 只允许对系统消息重生
        let cutoff = message.createdAt
        trimMessages(from: cutoff, inclusive: true)
        onUpdate?()

        let currentMessages = chronologicalMessages()
        isPriming = true
        isLoading = true
        sending = true
        chatService.fetchStreamedData(messages: currentMessages)
    }

    /// 错误气泡中的“重试”
    func retry(afterErrorMessage errorMessage: ChatMessage) {
        guard !sending else { return }
        chatService.cancelStreaming()
        closeActiveAssistantMessageIfAny()

        let errorTime = errorMessage.createdAt

        // 1) 先移除错误气泡自身
        if let idx = chatSession.messages.firstIndex(where: { $0.id == errorMessage.id }) {
            chatSession.messages.remove(at: idx)
        }

        // 2) 再移除“被中断”的那条助手消息（优先按记录的 ID；若无记录则回退为错误前最近的一条助手消息）
        if let interruptedID = interruptedAssistantMessageID,
           let idx2 = chatSession.messages.firstIndex(where: { $0.id == interruptedID }) {
            chatSession.messages.remove(at: idx2)
        } else {
            let candidates = chatSession.messages.enumerated()
                .filter { (_, m) in !m.isUser && m.createdAt <= errorTime && !m.content.hasPrefix("!error:") }
                .sorted(by: { $0.element.createdAt > $1.element.createdAt })
            if let (idx3, _) = candidates.first {
                chatSession.messages.remove(at: idx3)
            }
        }

        // 3) 额外清理：若“上一条靠近错误时间点的助手消息”是未闭合的 <think>，也删除
        if let idxThink = indexOfNearestUnclosedThinkAssistant(beforeOrAt: errorTime) {
            chatSession.messages.remove(at: idxThink)
        }

        // 清理标记
        interruptedAssistantMessageID = nil

        // 4) 以“清理后的历史（时间升序）”重新发起请求
        let currentMessages = chronologicalMessages()
        isPriming = true
        isLoading = true
        sending = true
        onUpdate?()

        chatService.fetchStreamedData(messages: currentMessages)
    }

    // MARK: - 编辑流程

    /// 进入编辑模式（仅“视觉隐藏”尾部，不立刻删除）
    func beginEditUserMessage(_ message: ChatMessage) {
        guard message.isUser else { return }
        editingBaseMessageID = message.id
        userMessage = message.content
    }

    /// 取消编辑（恢复可见，清空输入）
    func cancelEditing() {
        editingBaseMessageID = nil
        userMessage = ""
    }

    // MARK: - Helpers (retry 清理辅助)

    /// 返回“错误发生时间点之前（含）最靠近的、未闭合 <think> 的助手消息”的索引
    private func indexOfNearestUnclosedThinkAssistant(beforeOrAt time: Date) -> Int? {
        let enumerated = chatSession.messages.enumerated()
            .filter { (_, m) in
                guard !m.isUser, !m.content.hasPrefix("!error:") else { return false }
                return m.createdAt <= time
            }

        for (idx, msg) in enumerated.sorted(by: { $0.element.createdAt > $1.element.createdAt }) {
            if isUnclosedThink(msg.content) { return idx }
        }
        return nil
    }

    private func isUnclosedThink(_ text: String) -> Bool {
        guard let start = text.range(of: "<think>") else { return false }
        let after = text[start.upperBound...]
        return after.range(of: "</think>") == nil
    }
}
