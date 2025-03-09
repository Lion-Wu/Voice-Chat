//
//  ChatSessionsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Foundation

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
        let sessionsCopy = chatSessions
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(sessionsCopy)
                try data.write(to: path, options: .atomic)
            } catch {
                print("Error saving sessions: \(error)")
            }
        }
    }

    func loadChatSessions() {
        let path = chatSessionsFileURL()
        DispatchQueue.global(qos: .background).async {
            if let data = try? Data(contentsOf: path) {
                do {
                    let loaded = try JSONDecoder().decode([ChatSession].self, from: data)
                    DispatchQueue.main.async {
                        self.chatSessions = loaded
                        if self.selectedSessionID == nil {
                            self.selectedSessionID = self.chatSessions.first?.id
                        }
                        if self.chatSessions.isEmpty {
                            self.startNewSession()
                        }
                    }
                } catch {
                    print("load sessions error: \(error)")
                    DispatchQueue.main.async {
                        if self.chatSessions.isEmpty {
                            self.startNewSession()
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    if self.chatSessions.isEmpty {
                        self.startNewSession()
                    }
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
