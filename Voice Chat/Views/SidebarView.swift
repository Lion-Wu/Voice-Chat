//
//  SidebarView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import SwiftUI

private enum SidebarTimeSection: Int, CaseIterable, Identifiable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case pastYear
    case older

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .last7Days:
            return "Last 7 Days"
        case .last30Days:
            return "Last 30 Days"
        case .pastYear:
            return "Past Year"
        case .older:
            return "Older"
        }
    }

    static func from(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> SidebarTimeSection {
        if calendar.isDateInToday(date) {
            return .today
        }
        if calendar.isDateInYesterday(date) {
            return .yesterday
        }

        let startOfToday = calendar.startOfDay(for: Date())
        if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday),
           date >= sevenDaysAgo {
            return .last7Days
        }
        if let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday),
           date >= thirtyDaysAgo {
            return .last30Days
        }
        if let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: startOfToday),
           date >= oneYearAgo {
            return .pastYear
        }
        return .older
    }
}

private struct SidebarSessionGroup: Identifiable {
    let section: SidebarTimeSection
    let sessions: [ChatSession]

    var id: SidebarTimeSection { section }
}

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
    @State private var pendingDeleteSessionIDs: [UUID] = []

    private var filteredSessions: [ChatSession] {
        let keyword = searchKeyword
        guard !keyword.isEmpty else { return chatSessionsViewModel.chatSessions }
        return chatSessionsViewModel.chatSessions.filter { session in
            let titleMatch = session.title.localizedCaseInsensitiveContains(keyword)
            let messageMatch = session.messages.contains {
                $0.content.localizedCaseInsensitiveContains(keyword)
            }
            return titleMatch || messageMatch
        }
    }

    private var searchKeyword: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var groupedFilteredSessions: [SidebarSessionGroup] {
        let calendar = Calendar.autoupdatingCurrent
        var grouped: [SidebarTimeSection: [ChatSession]] = [:]

        for session in filteredSessions {
            let section = SidebarTimeSection.from(session.lastActivityAt, calendar: calendar)
            grouped[section, default: []].append(session)
        }

        return SidebarTimeSection.allCases.compactMap { section in
            guard let sessions = grouped[section], !sessions.isEmpty else { return nil }
            return SidebarSessionGroup(section: section, sessions: sessions)
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
                let indexes = Set(pendingDeleteSessionIDs.compactMap { sessionID in
                    chatSessionsViewModel.chatSessions.firstIndex(where: { $0.id == sessionID })
                })
                if !indexes.isEmpty {
                    let offsets = IndexSet(indexes)
                    chatSessionsViewModel.deleteSession(at: offsets)
                }
                pendingDeleteSessionIDs.removeAll()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteSessionIDs.removeAll()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Swipe Delete Hook

    private func handleSwipeDelete(at offsets: IndexSet, within sessions: [ChatSession]) {
        let sessionIDs = offsets.compactMap { offset -> UUID? in
            guard offset < sessions.count else { return nil }
            return sessions[offset].id
        }
        requestDelete(for: sessionIDs)
    }

    private func requestDelete(for session: ChatSession) {
        requestDelete(for: [session.id])
    }

    private func requestDelete(for sessionIDs: [UUID]) {
        var seen = Set<UUID>()
        let uniqueIDs = sessionIDs.filter { seen.insert($0).inserted }
        guard !uniqueIDs.isEmpty else { return }
        pendingDeleteSessionIDs = uniqueIDs
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
                        chatSessionsViewModel.renameSession(session, to: newTitle, reason: .immediate)
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

    private func selectDraftSession() {
        guard chatSessionsViewModel.canStartNewSession else { return }
        let draft = chatSessionsViewModel.draftSession
        chatSessionsViewModel.selectedSession = draft
        onConversationTap(draft)
    }

    @ViewBuilder
    private var macSidebar: some View {
        List(selection: $chatSessionsViewModel.selectedSessionID) {
            Section {
                macDraftRow
                    .tag(chatSessionsViewModel.draftSession.id)
            }
            if groupedFilteredSessions.isEmpty {
                Section(header: Text("Chats")) {
                    if searchKeyword.isEmpty {
                        Text("No chats yet")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(format: NSLocalizedString("No chats match \"%@\"", comment: ""), searchKeyword))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(groupedFilteredSessions) { group in
                    Section(header: Text(group.section.title)) {
                        ForEach(group.sessions) { session in
                            macSessionRow(session)
                                .tag(session.id)
                                .contextMenu {
                                    Button("Rename") { renameSession(session) }
                                    Button("Delete", role: .destructive) {
                                        requestDelete(for: session)
                                    }
                                }
                        }
                        .onDelete { offsets in
                            handleSwipeDelete(at: offsets, within: group.sessions)
                        }
                    }
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
        ZStack {
            AppBackgroundView()

            List(selection: $chatSessionsViewModel.selectedSessionID) {
                Section {
                    iosDraftRow
                        .tag(chatSessionsViewModel.draftSession.id)
                }
                if groupedFilteredSessions.isEmpty {
                    Section(LocalizedStringKey("Chats")) {
                        if searchKeyword.isEmpty {
                            ContentUnavailableView(
                                LocalizedStringKey("No chats yet"),
                                systemImage: "text.bubble",
                                description: Text("Start a new conversation to begin talking.")
                            )
                            .listRowBackground(Color.clear)
                        } else {
                            ContentUnavailableView(
                                LocalizedStringKey("No Results"),
                                systemImage: "magnifyingglass",
                                description: Text("Try a different chat name.")
                            )
                            .listRowBackground(Color.clear)
                        }
                    }
                } else {
                    ForEach(groupedFilteredSessions) { group in
                        Section(group.section.title) {
                            ForEach(group.sessions) { session in
                                iosSessionRow(session)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        chatSessionsViewModel.selectedSession = session
                                        onConversationTap(session)
                                    }
                                    .contextMenu {
                                        Button("Rename") { renameSession(session) }
                                        Button("Delete", role: .destructive) {
                                            requestDelete(for: session)
                                        }
                                    }
                                    .tag(session.id)
                            }
                            .onDelete { offsets in
                                handleSwipeDelete(at: offsets, within: group.sessions)
                            }
                        }
                    }
                }
            }
            #if os(iOS) || os(tvOS)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.automatic)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            #else
            .listStyle(.plain)
            #endif
        }
        .safeAreaInset(edge: .top, spacing: 0) { iosSearchHeaderContainer }
        #if os(iOS) || os(tvOS)
        .safeAreaInset(edge: .bottom) { iosSettingsFooter }
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iosSearchHeaderContainer: some View {
        VStack(spacing: 0) {
            iosSearchHeader
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(ChatTheme.separator)
        }
    }

    private var iosSearchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Chats", text: $searchText)
                .textFieldStyle(.plain)
#if os(iOS) || os(tvOS)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
#endif

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
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ChatTheme.subtleStroke.opacity(0.6), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
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

    private var macDraftRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)
            Text("New Chat")
                .font(.headline)
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { selectDraftSession() }
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

    private var iosDraftRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)
            Text("New Chat")
                .font(.body.weight(.semibold))
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { selectDraftSession() }
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
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.thinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(PlatformColor.systemBackground.opacity(0.05), lineWidth: 0.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }
    #endif
}

#Preview {
    SidebarView(
        onConversationTap: { _ in },
        onOpenSettings: {}
    )
    .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
    .environmentObject(ChatSessionsViewModel())
}
