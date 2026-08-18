//
//  SidebarView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import Combine
import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    var onConversationTap: (ChatSession) -> Void
    var onOpenSettings: () -> Void

    @State private var renamingSession: ChatSession? = nil
    @State private var newTitle: String = ""
    @State private var searchText: String = ""
    // Query that produced the currently visible sidebar results; it intentionally lags searchText during debounce.
    @State private var visibleSearchKeyword: String = ""
    @State private var sidebarGroups: [SidebarSessionGroup] = []
    @State private var appliedCalendarConfiguration: SidebarCalendarConfiguration?
    @State private var isSidebarSearchLoading: Bool = false
    @State private var sidebarSearchRefreshTask: Task<Void, Never>? = nil
    @State private var sidebarSelectionID: UUID?
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
        isSidebarSearchLoading && !searchKeyword.isEmpty
    }

    private var shouldShowInitialSessionLoading: Bool {
        SidebarSessionListLoadState.resolve(
            isPersistentStoreAttached: chatSessionsViewModel.isPersistentStoreAttached,
            hasSessions: !chatSessionsViewModel.chatSessions.isEmpty,
            hasPublishedGroups: !sidebarGroups.isEmpty,
            visibleSearchKeyword: visibleSearchKeyword
        ) == .loading
    }

    private var isSidebarSearchActive: Bool {
        !searchKeyword.isEmpty
    }

    private var appDisplayName: String {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
        ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
        ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
        ?? "Voice Chat"
    }

    @ViewBuilder
    private var sidebarSearchLoadingRow: some View {
        sidebarLoadingRow(title: "Searching...")
    }

    @ViewBuilder
    private var sidebarInitialLoadingRow: some View {
        sidebarLoadingRow(title: "Loading...")
    }

    private func sidebarLoadingRow(title: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(title)
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
        .onReceive(chatSessionsViewModel.sidebarContentDidChange) {
            scheduleSidebarSearchRefresh(debounce: !searchKeyword.isEmpty)
        }
        .onChange(of: searchText) { _, _ in
            scheduleSidebarSearchRefresh(debounce: !searchKeyword.isEmpty)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refreshSidebarGroupsForSystemCalendarChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            refreshSidebarGroupsForSystemCalendarChange()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshSidebarGroupsIfCalendarConfigurationChanged()
        }
        .onDisappear {
            sidebarSearchRefreshTask?.cancel()
            sidebarSearchRefreshTask = nil
        }
    }

    private func refreshSidebarGroupsForSystemCalendarChange() {
        scheduleSidebarSearchRefresh(
            debounce: false,
            calendar: .autoupdatingCurrent
        )
    }

    private func refreshSidebarGroupsIfCalendarConfigurationChanged() {
        let calendar = Calendar.autoupdatingCurrent
        guard SidebarCalendarConfiguration.needsRefresh(
            applied: appliedCalendarConfiguration,
            calendar: calendar
        ) else {
            return
        }
        scheduleSidebarSearchRefresh(debounce: false, calendar: calendar)
    }

    private func scheduleSidebarSearchRefresh(
        debounce: Bool,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let requestedKeyword = searchKeyword
        let requestedCalendarConfiguration = SidebarCalendarConfiguration(calendar: calendar)
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
                publishSidebarGroups(
                    SidebarSessionGrouping.groupedSessions(
                        chatSessionsViewModel.chatSessions,
                        calendar: calendar
                    )
                )
                appliedCalendarConfiguration = requestedCalendarConfiguration
                visibleSearchKeyword = requestedKeyword
                return
            }

            let candidates = chatSessionsViewModel.chatSessions
            var matchedSessions: [ChatSession] = []
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
                }

                startIndex = endIndex
                isSidebarSearchLoading = startIndex < candidates.count
                await Task.yield()
            }

            guard !Task.isCancelled else { return }
            isSidebarSearchLoading = false
            publishSidebarGroups(
                SidebarSessionGrouping.groupedSessions(
                    matchedSessions,
                    calendar: calendar
                )
            )
            appliedCalendarConfiguration = requestedCalendarConfiguration
            visibleSearchKeyword = requestedKeyword
        }
    }

    private func publishSidebarGroups(_ proposed: [SidebarSessionGroup]) {
        guard !SidebarSessionGrouping.hasSameLayout(
            sidebarGroups,
            as: proposed
        ) else {
            return
        }
        sidebarGroups = proposed
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

    private func selectMacSession(with sessionID: UUID?) {
        // A single-selection sidebar always has a valid app-level selection.
        // AppKit may transiently write nil while List rows are being reconciled;
        // accepting it would make the detail column fall back to the empty draft.
        guard let sessionID else { return }
        if sessionID == chatSessionsViewModel.draftSession.id {
            chatSessionsViewModel.selectedSession = chatSessionsViewModel.draftSession
            return
        }
        guard let session = chatSessionsViewModel.chatSessions.first(where: { $0.id == sessionID }) else {
            return
        }
        chatSessionsViewModel.selectSession(session, matchingSidebarQuery: visibleSearchKeyword)
    }

    private func synchronizeSidebarSelection(with sessionID: UUID?) {
        guard sidebarSelectionID != sessionID else { return }
        sidebarSelectionID = sessionID
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
        List(selection: $sidebarSelectionID) {
            Section {
                macDraftRow
                    .tag(chatSessionsViewModel.draftSession.id)
            }
            if shouldShowInitialSessionLoading || sidebarGroups.isEmpty {
                Section(header: Text("Chats")) {
                    if shouldShowInitialSessionLoading {
                        sidebarInitialLoadingRow
                    } else if visibleSearchKeyword.isEmpty {
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
                    Section(header: group.section.title) {
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
        .onChange(of: sidebarSelectionID) { _, sessionID in
            selectMacSession(with: sessionID)
        }
        .onChange(of: chatSessionsViewModel.selectedSessionID, initial: true) { _, sessionID in
            synchronizeSidebarSelection(with: sessionID)
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: Text("Search Chats"))
        #if os(macOS)
        .safeAreaInset(edge: .bottom) {
            SidebarSettingsFooter(style: .mac, onOpenSettings: onOpenSettings)
        }
        #endif
    }

    @ViewBuilder
    private var iosSidebarList: some View {
        List {
            if !isSidebarSearchActive {
                Section {
                    NavigationLink(value: ChatSessionNavigationRoute(
                        sessionID: chatSessionsViewModel.draftSession.id
                    )) {
                        iosDraftRowContent
                    }
                    .disabled(!chatSessionsViewModel.canStartNewSession)
                }
            }
            if shouldShowInitialSessionLoading || sidebarGroups.isEmpty {
                Section(LocalizedStringKey("Chats")) {
                    if shouldShowInitialSessionLoading {
                        sidebarInitialLoadingRow
                            .listRowBackground(Color.clear)
                    } else if visibleSearchKeyword.isEmpty {
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
                    Section {
                        ForEach(group.sessions) { session in
                            NavigationLink(value: ChatSessionNavigationRoute(
                                sessionID: session.id,
                                searchQuery: visibleSearchKeyword
                            )) {
                                iosSessionRow(session)
                            }
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
                    } header: {
                        group.section.title
                    }
                }
                sidebarSearchLoadingSection
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    @ViewBuilder
    private var iosSidebar: some View {
        #if os(iOS) || os(tvOS)
        #if os(iOS)
        iosSidebarList
            .listStyle(.insetGrouped)
            .navigationTitle(appDisplayName)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: Text("Search Chats"))
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .bottomBar) {
                        Button(action: onOpenSettings) {
                            Label("Settings", systemImage: "gear")
                        }
                    }

                    ToolbarSpacer(placement: .bottomBar)

                    DefaultToolbarItem(kind: .search, placement: .bottomBar)

                    ToolbarSpacer(placement: .bottomBar)

                    ToolbarItem(placement: .bottomBar) {
                        Button(action: selectDraftSession) {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                        .disabled(!chatSessionsViewModel.canStartNewSession)
                    }
                } else {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(action: onOpenSettings) {
                            Label("Settings", systemImage: "gear")
                        }

                        Spacer()

                        Button(action: selectDraftSession) {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                        .disabled(!chatSessionsViewModel.canStartNewSession)
                    }
                }
            }
        #else
        iosSidebarList
            .listStyle(.insetGrouped)
        #endif
        #else
        iosSidebarList
            .listStyle(.plain)
        #endif
    }

    private var visionSidebar: some View {
        List(selection: $sidebarSelectionID) {
            Section {
                iosDraftRow
                    .tag(chatSessionsViewModel.draftSession.id)
            }

            if shouldShowInitialSessionLoading || sidebarGroups.isEmpty {
                Section(LocalizedStringKey("Chats")) {
                    if shouldShowInitialSessionLoading {
                        sidebarInitialLoadingRow
                    } else if visibleSearchKeyword.isEmpty {
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
                    Section {
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
                    } header: {
                        group.section.title
                    }
                }
                sidebarSearchLoadingSection
            }
        }
        .onChange(of: sidebarSelectionID) { _, sessionID in
            selectMacSession(with: sessionID)
        }
        .onChange(of: chatSessionsViewModel.selectedSessionID, initial: true) { _, sessionID in
            synchronizeSidebarSelection(with: sessionID)
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
        .popover(isPresented: renamePopoverBinding(for: session), arrowEdge: .trailing) {
            renameSheetView()
        }
    }

    private var iosDraftRow: some View {
        iosDraftRowContent
            .contentShape(Rectangle())
            .onTapGesture { selectDraftSession() }
    }

    private var iosDraftRowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)
            Text("New Chat")
                .font(.body.weight(.semibold))
            Spacer()
        }
        .padding(.vertical, sidebarRowVerticalPadding)
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
    let chatSessions = ChatSessionsViewModel(
        settingsManager: settingsManager,
        reachability: ServerReachabilityMonitor.shared,
        audioManager: GlobalAudioManager.shared
    )
    let container = try! ModelContainer(
        for: Schema([
            ChatSession.self,
            ChatMessage.self,
            ChatRequestContextMetadata.self,
            AppSettings.self
        ]),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    _ = chatSessions.attach(context: container.mainContext)

    return SidebarView(
        onConversationTap: { _ in },
        onOpenSettings: {}
    )
    .modelContainer(container)
    .environmentObject(chatSessions)
}
