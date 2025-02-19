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
        // Only allow starting a new session if the currently selected session has some content
        // If selectedSession is nil or has no messages, return false
        if let session = selectedSession {
            return !session.messages.isEmpty
        }
        return false
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

    private func getDocumentsDirectory() -> URL {
        #if os(macOS)
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = paths[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "VoiceChat")
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        return appSupportURL
        #else
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
        #endif
    }

    private func chatSessionsFileURL() -> URL {
        return getDocumentsDirectory().appendingPathComponent("chat_sessions.json")
    }

    func saveChatSessions() {
        let currentSessions = chatSessions
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(currentSessions)
                try data.write(to: self.chatSessionsFileURL(), options: .atomic)
            } catch {
                print("Error saving chat sessions: \(error)")
            }
        }
    }

    func loadChatSessions() {
        DispatchQueue.global(qos: .background).async {
            let url = self.chatSessionsFileURL()
            if let data = try? Data(contentsOf: url) {
                do {
                    let decodedSessions = try JSONDecoder().decode([ChatSession].self, from: data)
                    DispatchQueue.main.async {
                        self.chatSessions = decodedSessions
                        if self.selectedSessionID == nil {
                            self.selectedSessionID = self.chatSessions.first?.id
                        }
                        if self.chatSessions.isEmpty {
                            self.startNewSession()
                        }
                    }
                } catch {
                    print("Error loading chat sessions: \(error)")
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
}
