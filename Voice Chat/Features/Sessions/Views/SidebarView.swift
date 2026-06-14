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

    @State private var renamingSession: ChatSession? = nil
    @State private var newTitle: String = ""
    @State private var searchText: String = ""
    // Query that produced the currently visible sidebar results; it intentionally lags searchText during debounce.
    @State private var visibleSearchKeyword: String = ""
    @State private var sidebarGroups: [SidebarSessionGroup] = []
    @State private var isSidebarSearchLoading: Bool = false
    @State private var sidebarSearchRefreshTask: Task<Void, Never>? = nil
    @FocusState private var isRenameFieldFocused: Bool

    // Deletion confirmation
    @State private var showDeleteChatAlert: Bool = false
    @State private var pendingDeleteSessionIDs: [UUID] = []

    private static let sidebarSearchDebounceNanoseconds: UInt64 = 180_000_000
    private static let sidebarSearchBatchSize: Int = 12

    private var searchKeyword: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRenameTitle: String {
        newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowSidebarSearchLoading: Bool {
        isSidebarSearchLoading && !visibleSearchKeyword.isEmpty
    }

    @ViewBuilder
    private var sidebarSearchLoadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Searching...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, sidebarRowVerticalPadding)
    }

    @ViewBuilder
    private var sidebarSearchLoadingSection: some View {
        if shouldShowSidebarSearchLoading {
            Section {
                sidebarSearchLoadingRow
            }
        }
    }

    var body: some View {
        Group {
            #if os(macOS)
            macSidebar
            #elseif os(visionOS)
            visionSidebar
            #else
            iosSidebar
            #endif
        }
        #if os(iOS) || os(tvOS) || os(visionOS)
        .alert("Rename Chat",
               isPresented: renameAlertBinding) {
            TextField("New Title", text: $newTitle)
            Button("Cancel", role: .cancel) {
                dismissRenameSheet()
            }
            Button("Save") {
                commitRename()
            }
            .disabled(trimmedRenameTitle.isEmpty)
        }
        #endif
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
        .onAppear {
            scheduleSidebarSearchRefresh(debounce: false)
        }
        .onReceive(chatSessionsViewModel.$chatSessions) { _ in
            scheduleSidebarSearchRefresh(debounce: !searchKeyword.isEmpty)
        }
        .onChange(of: searchText) { _, _ in
            scheduleSidebarSearchRefresh(debounce: !searchKeyword.isEmpty)
        }
        .onDisappear {
            sidebarSearchRefreshTask?.cancel()
            sidebarSearchRefreshTask = nil
        }
    }

    private func scheduleSidebarSearchRefresh(debounce: Bool) {
        let requestedKeyword = searchKeyword
        let shouldDebounce = debounce && !requestedKeyword.isEmpty
        sidebarSearchRefreshTask?.cancel()
        sidebarSearchRefreshTask = Task { @MainActor in
            if shouldDebounce {
                try? await Task.sleep(nanoseconds: Self.sidebarSearchDebounceNanoseconds)
                guard !Task.isCancelled else { return }
            }

            let normalizedQuery = chatSessionsViewModel.normalizedSidebarSearchQuery(requestedKeyword)
            if normalizedQuery.isEmpty {
                isSidebarSearchLoading = false
                sidebarGroups = SidebarSessionGrouping.groupedSessions(chatSessionsViewModel.chatSessions)
                visibleSearchKeyword = requestedKeyword
                return
            }

            let candidates = chatSessionsViewModel.chatSessions
            var matchedSessions: [ChatSession] = []
            visibleSearchKeyword = requestedKeyword
            sidebarGroups = []
            isSidebarSearchLoading = !candidates.isEmpty

            var startIndex = 0
            while startIndex < candidates.count {
                guard !Task.isCancelled else { return }

                let endIndex = min(startIndex + Self.sidebarSearchBatchSize, candidates.count)
                let batch = Array(candidates[startIndex..<endIndex])
                let newMatches = chatSessionsViewModel.sessions(
                    in: batch,
                    matchingNormalizedSidebarQuery: normalizedQuery
                )

                if !newMatches.isEmpty {
                    matchedSessions.append(contentsOf: newMatches)
                    sidebarGroups = SidebarSessionGrouping.groupedSessions(matchedSessions)
                }

                startIndex = endIndex
                isSidebarSearchLoading = startIndex < candidates.count
                await Task.yield()
            }

            guard !Task.isCancelled else { return }
            isSidebarSearchLoading = false
            visibleSearchKeyword = requestedKeyword
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

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingSession != nil },
            set: { isPresented in
                if !isPresented {
                    dismissRenameSheet()
                }
            }
        )
    }

    private func renamePopoverBinding(for session: ChatSession) -> Binding<Bool> {
        Binding(
            get: { renamingSession?.id == session.id },
            set: { isPresented in
                if !isPresented, renamingSession?.id == session.id {
                    dismissRenameSheet()
                }
            }
        )
    }

    @ViewBuilder
    private func renameSheetView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Chat")
                .font(.headline)
            TextField("New Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .focused($isRenameFieldFocused)
                .onSubmit(commitRename)
            HStack {
                Button("Cancel") {
                    dismissRenameSheet()
                }
                Spacer()
                Button("Save") {
                    commitRename()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedRenameTitle.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            isRenameFieldFocused = true
        }
    }

    private func renameSession(_ session: ChatSession) {
        renamingSession = session
        newTitle = session.title
    }

    private func dismissRenameSheet() {
        renamingSession = nil
        newTitle = ""
        isRenameFieldFocused = false
    }

    private func commitRename() {
        guard let session = renamingSession else {
            dismissRenameSheet()
            return
        }

        let title = trimmedRenameTitle
        guard !title.isEmpty else { return }

        chatSessionsViewModel.renameSession(session, to: title, reason: .immediate)
        dismissRenameSheet()
    }

    private func selectDraftSession() {
        guard chatSessionsViewModel.canStartNewSession else { return }
        let draft = chatSessionsViewModel.draftSession
        chatSessionsViewModel.selectedSession = draft
        onConversationTap(draft)
    }

    private func selectSessionFromSidebar(_ session: ChatSession) {
        chatSessionsViewModel.selectSession(session, matchingSidebarQuery: visibleSearchKeyword)
        onConversationTap(session)
    }

    private func sidebarPreview(for session: ChatSession) -> SidebarSessionPreview {
        chatSessionsViewModel.sidebarPreview(for: session, matchingSearchQuery: visibleSearchKeyword)
    }

    private func sidebarPreviewText(for preview: SidebarSessionPreview) -> Text {
        guard !preview.emphasizedRanges.isEmpty else {
            return Text(verbatim: preview.text)
        }

        var result = Text("")
        var cursor = preview.text.startIndex
        for nsRange in preview.emphasizedRanges {
            guard let range = Range(nsRange, in: preview.text),
                  range.lowerBound >= cursor else {
                continue
            }
            if cursor < range.lowerBound {
                result = result + Text(verbatim: String(preview.text[cursor..<range.lowerBound]))
            }
            result = result + Text(verbatim: String(preview.text[range])).bold()
            cursor = range.upperBound
        }
        if cursor < preview.text.endIndex {
            result = result + Text(verbatim: String(preview.text[cursor..<preview.text.endIndex]))
        }
        return result
    }

    @ViewBuilder
    private var macSidebar: some View {
        List(selection: $chatSessionsViewModel.selectedSessionID) {
            Section {
                macDraftRow
                    .tag(chatSessionsViewModel.draftSession.id)
            }
            if sidebarGroups.isEmpty {
                Section(header: Text("Chats")) {
                    if visibleSearchKeyword.isEmpty {
                        Text("No chats yet")
                            .foregroundStyle(.secondary)
                    } else if shouldShowSidebarSearchLoading {
                        sidebarSearchLoadingRow
                    } else {
                        Text(String(format: NSLocalizedString("No chats match \"%@\"", comment: ""), visibleSearchKeyword))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(sidebarGroups) { group in
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
                sidebarSearchLoadingSection
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: Text("Search Chats"))
        #if os(macOS)
        .safeAreaInset(edge: .bottom) {
            SidebarSettingsFooter(style: .mac, onOpenSettings: onOpenSettings)
        }
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
                if sidebarGroups.isEmpty {
                    Section(LocalizedStringKey("Chats")) {
                        if visibleSearchKeyword.isEmpty {
                            ContentUnavailableView(
                                LocalizedStringKey("No chats yet"),
                                systemImage: "text.bubble",
                                description: Text("Start a new conversation to begin talking.")
                            )
                            .listRowBackground(Color.clear)
                        } else if shouldShowSidebarSearchLoading {
                            sidebarSearchLoadingRow
                                .listRowBackground(Color.clear)
                        } else {
                            ContentUnavailableView(
                                LocalizedStringKey("No Results"),
                                systemImage: "magnifyingglass",
                                description: Text("Try a different search.")
                            )
                            .listRowBackground(Color.clear)
                        }
                    }
                } else {
                    ForEach(sidebarGroups) { group in
                        Section(group.section.title) {
                            ForEach(group.sessions) { session in
                                iosSessionRow(session)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectSessionFromSidebar(session)
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
                    sidebarSearchLoadingSection
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
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarSearchHeader(style: .touch, searchText: $searchText)
        }
        #if os(iOS) || os(tvOS)
        .safeAreaInset(edge: .bottom) {
            SidebarSettingsFooter(style: .touch, onOpenSettings: onOpenSettings)
        }
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visionSidebar: some View {
        List(selection: $chatSessionsViewModel.selectedSessionID) {
            Section {
                iosDraftRow
                    .tag(chatSessionsViewModel.draftSession.id)
            }

            if sidebarGroups.isEmpty {
                Section(LocalizedStringKey("Chats")) {
                    if visibleSearchKeyword.isEmpty {
                        ContentUnavailableView(
                            LocalizedStringKey("No chats yet"),
                            systemImage: "text.bubble",
                            description: Text("Start a new conversation to begin talking.")
                        )
                    } else if shouldShowSidebarSearchLoading {
                        sidebarSearchLoadingRow
                    } else {
                        ContentUnavailableView(
                            LocalizedStringKey("No Results"),
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search.")
                        )
                    }
                }
            } else {
                ForEach(sidebarGroups) { group in
                    Section(group.section.title) {
                        ForEach(group.sessions) { session in
                            iosSessionRow(session)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectSessionFromSidebar(session)
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
                sidebarSearchLoadingSection
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 10) {
            SidebarSearchHeader(style: .vision, searchText: $searchText)
        }
        .safeAreaInset(edge: .bottom) {
            SidebarSettingsFooter(style: .vision, onOpenSettings: onOpenSettings)
        }
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
                sidebarPreviewText(for: sidebarPreview(for: session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectSessionFromSidebar(session)
        }
        .popover(isPresented: renamePopoverBinding(for: session), arrowEdge: .trailing) {
            renameSheetView()
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
        .padding(.vertical, sidebarRowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { selectDraftSession() }
    }

    private func iosSessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                sidebarPreviewText(for: sidebarPreview(for: session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, sidebarRowVerticalPadding)
    }

    private var sidebarRowVerticalPadding: CGFloat {
        #if os(visionOS)
        return 10
        #else
        return 6
        #endif
    }

}

#Preview {
    let settingsManager = SettingsManager.shared
    SidebarView(
        onConversationTap: { _ in },
        onOpenSettings: {}
    )
    .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
    .environmentObject(ChatSessionsViewModel(
        settingsManager: settingsManager,
        reachability: ServerReachabilityMonitor.shared,
        audioManager: GlobalAudioManager.shared
    ))
}
