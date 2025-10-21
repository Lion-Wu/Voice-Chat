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

    // Deletion confirmation state
    @State private var showDeleteChatAlert: Bool = false
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var pendingDeleteSingleIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $chatSessionsViewModel.selectedSessionID) {
                Section(header: Text(L10n.Sidebar.chatsHeader)) {
                    ForEach(chatSessionsViewModel.chatSessions) { session in
                        HStack {
                            Text(session.title)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onConversationTap(session) }
                        .contextMenu {
                            Button(L10n.Sidebar.rename) { renameSession(session) }
                            Button(L10n.Sidebar.delete, role: .destructive) {
                                if let idx = chatSessionsViewModel.chatSessions.firstIndex(where: { $0.id == session.id }) {
                                    pendingDeleteSingleIndex = idx
                                    pendingDeleteOffsets = nil
                                    showDeleteChatAlert = true
                                }
                            }
                        }
                    }
                    .onDelete(perform: handleSwipeDelete)
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button(action: onOpenSettings) {
                Label(L10n.Sidebar.settings, systemImage: "gearshape.fill")
                    .font(.system(.headline))
                    .padding()
            }
        }
        .sheet(isPresented: $isRenaming) { renameSheetView() }
        .alert(L10n.Sidebar.deleteChatTitle,
               isPresented: $showDeleteChatAlert) {
            Button(L10n.Common.delete, role: .destructive) {
                if let idx = pendingDeleteSingleIndex {
                    chatSessionsViewModel.deleteSession(at: IndexSet(integer: idx))
                    pendingDeleteSingleIndex = nil
                } else if let offsets = pendingDeleteOffsets {
                    chatSessionsViewModel.deleteSession(at: offsets)
                    pendingDeleteOffsets = nil
                }
            }
            Button(L10n.Common.cancel, role: .cancel) {
                pendingDeleteSingleIndex = nil
                pendingDeleteOffsets = nil
            }
        } message: {
            Text(L10n.Common.irreversibleActionMessage)
        }
    }

    // MARK: - Swipe Delete Hook

    private func handleSwipeDelete(at offsets: IndexSet) {
        pendingDeleteOffsets = offsets
        pendingDeleteSingleIndex = nil
        showDeleteChatAlert = true
    }

    // MARK: - Rename

    @ViewBuilder
    private func renameSheetView() -> some View {
        VStack(spacing: 20) {
            Text(L10n.Sidebar.renameChatTitle)
                .font(.headline)
            TextField(L10n.Sidebar.newTitlePlaceholder, text: $newTitle)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            HStack {
                Button(L10n.Common.cancel) { isRenaming = false }
                Spacer()
                Button(L10n.Common.save) {
                    if let session = renamingSession {
                        session.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        chatSessionsViewModel.persist(session: session, reason: .immediate)
                    }
                    isRenaming = false
                }
            }
        }
        .padding()
        .frame(width: 300)
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
        .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
        .environmentObject(ChatSessionsViewModel())
    }
}
