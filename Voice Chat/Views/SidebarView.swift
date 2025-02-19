//
//  SidebarView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    var onConversationTap: (ChatSession) -> Void
    var onOpenSettings: () -> Void

    @State private var isRenaming: Bool = false
    @State private var renamingSession: ChatSession? = nil
    @State private var newTitle: String = ""

    var body: some View {
        List(selection: $chatSessionsViewModel.selectedSessionID) {
            Section(header: Text("Chats")) {
                ForEach(chatSessionsViewModel.chatSessions) { session in
                    HStack {
                        Text(session.title)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onConversationTap(session)
                    }
                    .contextMenu {
                        Button("Rename") {
                            renameSession(session)
                        }
                        Button("Delete") {
                            if let index = chatSessionsViewModel.chatSessions.firstIndex(of: session) {
                                chatSessionsViewModel.deleteSession(at: IndexSet(integer: index))
                            }
                        }
                    }
                }
                .onDelete(perform: chatSessionsViewModel.deleteSession)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Chats")
        .toolbar {
            // Settings button in the toolbar for macOS
            ToolbarItem(placement: .automatic) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $isRenaming) {
            VStack(spacing: 20) {
                Text("Rename Chat")
                    .font(.headline)
                TextField("New Title", text: $newTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                HStack {
                    Button("Cancel") {
                        isRenaming = false
                    }
                    Spacer()
                    Button("Save") {
                        if let session = renamingSession {
                            session.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            chatSessionsViewModel.saveChatSessions()
                        }
                        isRenaming = false
                    }
                }
            }
            .padding()
            .frame(width: 300)
        }
    }

    private func renameSession(_ session: ChatSession) {
        renamingSession = session
        newTitle = session.title
        isRenaming = true
    }
}

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarView(
            onConversationTap: { _ in },
            onOpenSettings: {}
        )
        .environmentObject(ChatSessionsViewModel())
    }
}

