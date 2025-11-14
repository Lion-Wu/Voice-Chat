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
    @State private var searchText: String = ""

    // Deletion confirmation
    @State private var showDeleteChatAlert: Bool = false
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var pendingDeleteSingleIndex: Int?

    private var filteredSessions: [ChatSession] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return chatSessionsViewModel.chatSessions }
        return chatSessionsViewModel.chatSessions.filter { session in
            let titleMatch = session.title.localizedCaseInsensitiveContains(keyword)
            let messageMatch = session.messages.contains {
                $0.content.localizedCaseInsensitiveContains(keyword)
            }
            return titleMatch || messageMatch
        }
    }

    var body: some View {
        Group {
            #if os(macOS)
            macSidebar
            #else
            iosSidebar
            #endif
        }
        .sheet(isPresented: $isRenaming) { renameSheetView() }
        .alert("Delete chat?",
               isPresented: $showDeleteChatAlert) {
            Button("Delete", role: .destructive) {
                if let idx = pendingDeleteSingleIndex {
                    chatSessionsViewModel.deleteSession(at: IndexSet(integer: idx))
                    pendingDeleteSingleIndex = nil
                } else if let offsets = pendingDeleteOffsets {
                    chatSessionsViewModel.deleteSession(at: offsets)
                    pendingDeleteOffsets = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteSingleIndex = nil
                pendingDeleteOffsets = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Swipe Delete Hook

    private func handleSwipeDelete(at filteredOffsets: IndexSet) {
        let mapped = IndexSet(filteredOffsets.compactMap { offset -> Int? in
            guard offset < filteredSessions.count else { return nil }
            let session = filteredSessions[offset]
            return chatSessionsViewModel.chatSessions.firstIndex(where: { $0.id == session.id })
        })
        guard !mapped.isEmpty else { return }
        pendingDeleteOffsets = mapped
        pendingDeleteSingleIndex = nil
        showDeleteChatAlert = true
    }

    // MARK: - Rename

    @ViewBuilder
    private func renameSheetView() -> some View {
        VStack(spacing: 20) {
            Text("Rename Chat")
                .font(.headline)
            TextField("New Title", text: $newTitle)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            HStack {
                Button("Cancel") { isRenaming = false }
                Spacer()
                Button("Save") {
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

    @ViewBuilder
    private var macSidebar: some View {
        List(selection: $chatSessionsViewModel.selectedSessionID) {
            Section(header: Text("Chats")) {
                if filteredSessions.isEmpty {
                    Text(String(format: NSLocalizedString("No chats match \"%@\"", comment: ""), searchText))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredSessions) { session in
                        macSessionRow(session)
                            .tag(session.id)
                            .contextMenu {
                                Button("Rename") { renameSession(session) }
                                Button("Delete", role: .destructive) {
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
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: Text("Search Chats"))
        #if os(macOS)
        .safeAreaInset(edge: .bottom) { macSettingsFooter }
        #endif
    }

    private var iosSidebar: some View {
        VStack(spacing: 8) {
            iosSearchHeader

            List(selection: $chatSessionsViewModel.selectedSessionID) {
                Section(LocalizedStringKey("Chats")) {
                    if filteredSessions.isEmpty {
                        ContentUnavailableView(
                            LocalizedStringKey("No Results"),
                            systemImage: "magnifyingglass",
                            description: Text("Try a different chat name.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredSessions) { session in
                            iosSessionRow(session)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    chatSessionsViewModel.selectedSession = session
                                    onConversationTap(session)
                                }
                                .contextMenu {
                                    Button("Rename") { renameSession(session) }
                                    Button("Delete", role: .destructive) {
                                        if let idx = chatSessionsViewModel.chatSessions.firstIndex(where: { $0.id == session.id }) {
                                            pendingDeleteSingleIndex = idx
                                            pendingDeleteOffsets = nil
                                            showDeleteChatAlert = true
                                        }
                                    }
                                }
                                .tag(session.id)
                        }
                        .onDelete(perform: handleSwipeDelete)
                    }
                }
            }
            #if os(iOS) || os(tvOS)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.automatic)
            #else
            .listStyle(.plain)
            #endif
            #if os(iOS) || os(tvOS)
            .safeAreaInset(edge: .bottom) { iosSettingsFooter }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iosSearchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Chats", text: $searchText)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear Search"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PlatformColor.elevatedFill)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func sessionInitials(_ session: ChatSession) -> String {
        let trimmedTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return "VC" }
        let components = trimmedTitle.split(separator: " ")
        if components.count >= 2 {
            return components.prefix(2)
                .compactMap { $0.first }
                .map { String($0) }
                .joined()
                .uppercased()
        }
        return trimmedTitle.prefix(2).uppercased()
    }

    private func subtitle(for session: ChatSession) -> String {
        if let last = session.messages.max(by: { $0.createdAt < $1.createdAt })?.content {
            let parts = last.extractThinkParts()
            let trimmed = parts.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "No recent replies" }
            let snippet = trimmed.prefix(60)
            return trimmed.count > 60 ? "\(snippet)…" : String(snippet)
        }
        return "Fresh conversation"
    }

    private func macSessionRow(_ session: ChatSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle(for: session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            chatSessionsViewModel.selectedSession = session
            onConversationTap(session)
        }
    }

    private func iosSessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle(for: session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    #if os(macOS)
    private var macSettingsFooter: some View {
        VStack(spacing: 0) {
            Divider()
            SettingsLink {
                Label(LocalizedStringKey("Settings"), systemImage: "gearshape.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
    #else
    private var iosSettingsFooter: some View {
        VStack(spacing: 10) {
            Button(action: onOpenSettings) {
                Label(LocalizedStringKey("Settings"), systemImage: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }
    #endif
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
