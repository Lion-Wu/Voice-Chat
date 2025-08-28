//
//  ChatSessionsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation

// MARK: - 文件存取 Actor（专职后台 I/O，避免跨 Actor 违规调用）
private actor ChatSessionsFileStore {
    func write(data: Data, to url: URL) async throws {
        try data.write(to: url, options: .atomic)
    }

    func read(from url: URL) async -> Data? {
        return try? Data(contentsOf: url)
    }
}

@MainActor
final class ChatSessionsViewModel: ObservableObject {
    // MARK: - Published State
    @Published var chatSessions: [ChatSession] = []
    @Published var selectedSessionID: UUID? = nil

    // MARK: - Derived
    var selectedSession: ChatSession? {
        get {
            guard let id = selectedSessionID else { return nil }
            return chatSessions.first(where: { $0.id == id })
        }
        set {
            selectedSessionID = newValue?.id
        }
    }

    var canStartNewSession: Bool {
        if let s = selectedSession {
            return !s.messages.isEmpty
        }
        return true
    }

    // MARK: - Dependencies
    private let fileStore = ChatSessionsFileStore()

    // MARK: - Init
    init() {
        // 启动时异步加载
        loadChatSessions()
    }

    // MARK: - Session Ops
    func startNewSession() {
        let newSession = ChatSession()
        chatSessions.insert(newSession, at: 0)
        selectedSessionID = newSession.id
        saveChatSessions()
    }

    func addSession(_ session: ChatSession) {
        if !chatSessions.contains(session) {
            chatSessions.insert(session, at: 0)
            saveChatSessions()
        }
    }

    func deleteSession(at offsets: IndexSet) {
        chatSessions.remove(atOffsets: offsets)
        if !chatSessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = chatSessions.first?.id
        }
        saveChatSessions()
    }

    // MARK: - Persistence (并发安全)
    /// 主 Actor 上编码数据，然后交给后台 actor 写入磁盘
    func saveChatSessions() {
        let url = chatSessionsFileURL()

        // 在主 Actor 上先把引用类型编码为 Data，避免把非 Sendable 跨 Actor 传递
        let encodedData: Data
        do {
            encodedData = try JSONEncoder().encode(chatSessions)
        } catch {
            print("Error saving sessions (encode failed): \(error)")
            return
        }

        // 后台 actor 负责写入磁盘
        Task.detached { [fileStore] in
            do {
                try await fileStore.write(data: encodedData, to: url)
            } catch {
                // 仅日志，不回调到 UI
                print("Error saving sessions (write failed): \(error)")
            }
        }
    }

    /// 异步从磁盘加载，会在后台 actor 读取，再切回主 Actor 更新 UI
    func loadChatSessions() {
        let url = chatSessionsFileURL()

        Task.detached { [fileStore] in
            let data = await fileStore.read(from: url)

            let loadedSessions: [ChatSession]
            if let data {
                do {
                    loadedSessions = try JSONDecoder().decode([ChatSession].self, from: data)
                } catch {
                    print("load sessions error: \(error)")
                    loadedSessions = []
                }
            } else {
                loadedSessions = []
            }

            await MainActor.run {
                self.chatSessions = loadedSessions
                if self.selectedSessionID == nil {
                    self.selectedSessionID = self.chatSessions.first?.id
                }
                if self.chatSessions.isEmpty {
                    self.startNewSession()
                }
            }
        }
    }

    // MARK: - File URL
    private func chatSessionsFileURL() -> URL {
        #if os(iOS) || os(tvOS)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("chat_sessions.json")
        #elseif os(macOS)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "VoiceChat")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            // 即使创建失败，也返回上层路径，后续写入可能失败但不会崩溃
            print("Failed to create Application Support directory: \(error)")
        }
        return dir.appendingPathComponent("chat_sessions.json")
        #else
        return URL(fileURLWithPath: "/tmp/chat_sessions.json")
        #endif
    }
}
