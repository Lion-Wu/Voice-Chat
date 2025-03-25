//
//  ChatSessionsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation

@MainActor
class ChatSessionsViewModel: ObservableObject {
    @Published var chatSessions: [ChatSession] = []
    @Published var selectedSessionID: UUID? = nil

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
        // 自行决定何时允许新会话
        if let s = selectedSession {
            return !s.messages.isEmpty
        }
        return true
    }

    init() {
        loadChatSessions()
    }

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

    func saveChatSessions() {
        let path = chatSessionsFileURL()

        // 先在当前线程（主 actor）把 chatSessions 编码成 Data
        let encodedData: Data
        do {
            encodedData = try JSONEncoder().encode(chatSessions)
        } catch {
            print("Error saving sessions (encode failed): \(error)")
            return
        }

        // 把 Data 丢到后台线程写文件，避免直接跨 actor 捕获 chatSessions/self
        DispatchQueue.global(qos: .background).async {
            do {
                try encodedData.write(to: path, options: .atomic)
            } catch {
                print("Error saving sessions (write failed): \(error)")
            }
        }
    }

    func loadChatSessions() {
        let path = chatSessionsFileURL()

        DispatchQueue.global(qos: .background).async {
            // 后台线程读取文件并解码
            let data = try? Data(contentsOf: path)
            let loadedSessions: [ChatSession]

            if let data = data {
                do {
                    loadedSessions = try JSONDecoder().decode([ChatSession].self, from: data)
                } catch {
                    print("load sessions error: \(error)")
                    loadedSessions = []
                }
            } else {
                loadedSessions = []
            }

            // 回到主 actor 更新 UI
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

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

    private func chatSessionsFileURL() -> URL {
        #if os(iOS) || os(tvOS)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("chat_sessions.json")
        #elseif os(macOS)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "VoiceChat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("chat_sessions.json")
        #else
        return URL(fileURLWithPath: "/tmp/chat_sessions.json")
        #endif
    }
}
