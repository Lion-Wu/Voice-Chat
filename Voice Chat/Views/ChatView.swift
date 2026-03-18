//
//  ChatView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import SwiftUI
import Foundation
import SwiftData
import Combine
#if os(iOS) || os(macOS)
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
#endif

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Equatable Rendering Helpers

/// Wrapper that invalidates the view only when the equatable value changes.
@MainActor
private struct EquatableRender<Value: Equatable & Sendable, Content: View>: View, Equatable {
    nonisolated static func == (lhs: EquatableRender<Value, Content>, rhs: EquatableRender<Value, Content>) -> Bool {
        lhs.value == rhs.value
    }

    nonisolated let value: Value
    let content: () -> Content
    var body: some View { content() }
}

/// Equatable key for message rendering that keeps only UI-relevant fields.
private struct VoiceMessageEqKey: Equatable, Sendable {
    let id: UUID
    let isUser: Bool
    let isActive: Bool
    let imageAttachmentsFP: Int
    let branchRenderEpoch: Int
    let showActionButtons: Bool
    let branchControlsEnabled: Bool
    let contentFP: ContentFingerprint
    let developerModeEnabled: Bool
}

private enum ScrollTarget: Hashable {
    case bottom
}

private struct TextSelectionSheetItem: Identifiable {
    let id = UUID()
    let text: String
}

private struct ChatViewPlatformTitleModifier: ViewModifier {
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content.navigationTitle(title)
        #else
        content
        #endif
    }
}

#if os(iOS) || os(macOS)
private struct ImageDropSuppressionState {
    let signature: String
    let expiresAt: Date
}

private struct ImageAttachmentDropDelegate: DropDelegate {
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    @Binding var suppressionState: ImageDropSuppressionState?
    let acceptedTypeIdentifiers: [String]
    let filterProviders: ([NSItemProvider]) -> [NSItemProvider]
    let importProviders: ([NSItemProvider]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !imageProviders(from: info).isEmpty
    }

    func dropEntered(info: DropInfo) {
        guard !isSuppressed(info: info) else {
            isTargeted = false
            return
        }
        isTargeted = !imageProviders(from: info).isEmpty
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard !isSuppressed(info: info) else {
            isTargeted = false
            return nil
        }
        let hasImageProviders = !imageProviders(from: info).isEmpty
        isTargeted = hasImageProviders
        return hasImageProviders ? DropProposal(operation: .copy) : nil
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        if suppressionExpired {
            suppressionState = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let rawProviders = info.itemProviders(for: acceptedTypeIdentifiers)
        let providers = filterProviders(rawProviders)
        if !rawProviders.isEmpty {
            suppressionState = ImageDropSuppressionState(
                signature: Self.providerSignature(for: rawProviders),
                expiresAt: Date().addingTimeInterval(1.5)
            )
        }
        isTargeted = false
        guard !providers.isEmpty else {
            return false
        }
        importProviders(providers)
        return true
    }

    private func imageProviders(from info: DropInfo) -> [NSItemProvider] {
        guard isEnabled, !isSuppressed(info: info) else { return [] }
        return filterProviders(info.itemProviders(for: acceptedTypeIdentifiers))
    }

    private func isSuppressed(info: DropInfo) -> Bool {
        guard let suppressionState else { return false }
        guard !suppressionExpired else {
            self.suppressionState = nil
            return false
        }

        return suppressionState.signature == Self.providerSignature(for: info.itemProviders(for: acceptedTypeIdentifiers))
    }

    private var suppressionExpired: Bool {
        guard let suppressionState else { return true }
        return Date() >= suppressionState.expiresAt
    }

    private static func providerSignature(for providers: [NSItemProvider]) -> String {
        providers.map { provider in
            let name = provider.suggestedName ?? ""
            let types = provider.registeredTypeIdentifiers.sorted().joined(separator: ",")
            return "\(name)|\(types)"
        }
        .joined(separator: "||")
    }
}
#endif

struct ChatView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var errorCenter: AppErrorCenter
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject var viewModel: ChatViewModel
    @State private var textFieldHeight: CGFloat = InputMetrics.defaultHeight
    @State private var editingBannerHeight: CGFloat = 0
    @State private var availableMessageWidth: CGFloat = 680
    @FocusState private var isInputFocused: Bool

    @State private var textSelectionSheetItem: TextSelectionSheetItem?

    @State private var inputOverflow: Bool = false
    @State private var showFullScreenComposer: Bool = false

    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var bottomAnchorMaxY: CGFloat = 0
    @State private var showScrollToBottomButton: Bool = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var visibleMessages: [ChatMessage] = []
    @State private var fingerprintCache: [UUID: ContentFingerprint] = [:]
    @State private var lastReportedVisibleCount: Int = 0
    @State private var lastReportedSessionID: UUID? = nil
    @State private var isHydratingSession: Bool = false
    @State private var hydrationTask: Task<Void, Never>?
    @State private var pendingRefreshAfterHydration: Bool = false
    @State private var refreshGeneration = UUID()
    @State private var branchRenderEpoch: Int = 0
    @State private var showStartVoiceModeInterruptAlert: Bool = false
    @State private var showUnsupportedImageSendAlert: Bool = false
    @State private var expectAssistantResponseHaptics: Bool = false
    @State private var didTriggerResponseStartHaptic: Bool = false
#if os(iOS) || os(macOS)
    private enum ImageImportSource {
        case photoPicker
        case other
    }

    private struct ImageImportPayload: Sendable {
        let data: Data
        let mimeType: String?
    }

    private static let maxPendingImageAttachments = 9
    nonisolated private static let imageProcessingQueue = DispatchQueue(
        label: "com.lionwu.voicechat.image-processing",
        qos: .utility,
        attributes: .concurrent
    )

    @State private var showPhotoPicker: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var pickedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingPreviewFileURL: URL?
    @State private var imageImportTasks: [UUID: Task<Void, Never>] = [:]
    @State private var activePhotoImportID: UUID?
    @State private var isImageDropTargeted: Bool = false
    @State private var imageDropSuppressionState: ImageDropSuppressionState?
#endif

#if os(macOS)
    @State private var returnKeyMonitor: Any?
#endif

    // View model that coordinates the realtime voice overlay.
    @EnvironmentObject private var voiceOverlayVM: VoiceChatOverlayViewModel

    var onMessagesCountChange: (Int) -> Void = { _ in }

    init(viewModel: ChatViewModel, onMessagesCountChange: @escaping (Int) -> Void = { _ in }) {
        self.viewModel = viewModel
        self.onMessagesCountChange = onMessagesCountChange
    }

    /// Height of the scrollable content excluding the spacer that keeps it clear of the floating input.
    private var effectiveContentHeight: CGFloat {
        max(0, contentHeight - messageListBottomInset)
    }

    private var shouldAnchorBottom: Bool {
        guard viewportHeight > 0 else { return false }
        return effectiveContentHeight > (viewportHeight + 1)
    }

    private var messageListHorizontalPadding: CGFloat {
        #if os(macOS)
        return 16
        #else
        return 8
        #endif
    }

    private var floatingInputButtonHeight: CGFloat {
        textFieldHeight + InputMetrics.outerV * 2
    }

    private var pendingAttachmentStripHeight: CGFloat {
        guard !viewModel.pendingImageAttachments.isEmpty else { return 0 }
        return 88
    }

    private var floatingInputPanelHeight: CGFloat {
        floatingInputButtonHeight + composerOuterVerticalPadding * 2 + pendingAttachmentStripHeight
    }

    private var composerBottomPadding: CGFloat {
        #if os(iOS) || os(tvOS)
        return 26
        #else
        return 14
        #endif
    }

    private var composerOuterVerticalPadding: CGFloat {
        #if os(iOS) || os(tvOS)
        return 6
        #else
        return 8
        #endif
    }

    private var editingBannerEstimatedHeight: CGFloat {
        #if os(iOS) || os(tvOS)
        return 40
        #else
        return 38
        #endif
    }

    private var editingBannerInset: CGFloat {
        guard viewModel.isEditing else { return 0 }
        return max(editingBannerHeight, editingBannerEstimatedHeight)
    }

    private var messageListBottomInset: CGFloat {
        return floatingInputPanelHeight + composerBottomPadding + 6 + editingBannerInset
    }

    private var composerHeightForNotice: CGFloat {
        floatingInputPanelHeight + editingBannerInset
    }

    private var noticeBottomPadding: CGFloat {
        // Keep a stable gap above the floating composer regardless of input height growth.
        composerBottomPadding + composerHeightForNotice + 8
    }

    private var shouldDisplayAudioPlayer: Bool {
        audioManager.isShowingAudioPlayer && !audioManager.isRealtimeMode && !voiceOverlayVM.isPresented
    }

    private var trimmedUserMessage: String {
        viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSendDraft: Bool {
        !trimmedUserMessage.isEmpty || viewModel.hasPendingImageAttachments
    }

    private var currentModelSupportsImageInput: Bool {
        viewModel.currentModelSupportsImageInput()
    }

    private func refreshVisibleMessages(hydrating: Bool = false) {
        let token = UUID()
        refreshGeneration = token

        if hydrating {
            beginHydration(token: token)
            return
        }

        if hydrationTask != nil || isHydratingSession {
            pendingRefreshAfterHydration = true
            return
        }
        pendingRefreshAfterHydration = false

        let ordered = viewModel.orderedMessagesCached()
        let newVisible: [ChatMessage]
        if let baseID = viewModel.editingBaseMessageID,
           let idx = ordered.firstIndex(where: { $0.id == baseID }) {
            newVisible = Array(ordered.prefix(idx))
        } else {
            newVisible = ordered
        }

        updateVisibleMessages(newVisible, token: token)
    }

    private func beginHydration(token: UUID) {
        hydrationTask?.cancel()
        let ordered = viewModel.orderedMessagesCached()
        let target: [ChatMessage]
        if let baseID = viewModel.editingBaseMessageID,
           let idx = ordered.firstIndex(where: { $0.id == baseID }) {
            target = Array(ordered.prefix(idx))
        } else {
            target = ordered
        }

        isHydratingSession = true
        visibleMessages.removeAll(keepingCapacity: true)
        fingerprintCache.removeAll(keepingCapacity: true)
        MessageRenderCache.shared.clear()

        let snapshots = target.map { ($0.id, $0.content) }
        let fingerprintTask = Task.detached(priority: .userInitiated) {
            Self.buildFingerprints(from: snapshots)
        }

        hydrationTask = Task { @MainActor [target, snapshots, fingerprintTask, token] in
            let chunkSize = 48
            var idx = 0

            while idx < target.count {
                if Task.isCancelled || token != refreshGeneration { break }
                let upper = min(idx + chunkSize, target.count)
                let slice = target[idx..<upper]
                visibleMessages.append(contentsOf: slice)
                idx = upper
                if target.count > chunkSize {
                    await Task.yield()
                }
            }

            let shouldApply = !Task.isCancelled && token == refreshGeneration

            if !shouldApply {
                fingerprintTask.cancel()
            } else {
                let fingerprints = await fingerprintTask.value
                guard token == refreshGeneration else { return }
                let liveUpdates = fingerprintCache
                fingerprintCache = fingerprints.merging(liveUpdates) { _, newer in newer }
                finalizeVisibleState(targetCount: target.count)
                prewarmThinkParts(for: snapshots)
            }

            isHydratingSession = false
            hydrationTask = nil

            if pendingRefreshAfterHydration {
                pendingRefreshAfterHydration = false
                refreshVisibleMessages()
            }
        }
    }

    private func updateVisibleMessages(_ newVisible: [ChatMessage], token: UUID) {
        let newVisibleCopy = newVisible
        let visibleIDs = Set(newVisibleCopy.map(\.id))
        let missing = newVisibleCopy
            .filter { fingerprintCache[$0.id] == nil }
            .map { ($0.id, $0.content) }

        if missing.isEmpty {
            fingerprintCache = pruneFingerprints(fingerprintCache, keepingOnly: visibleIDs)
            visibleMessages = newVisibleCopy
            finalizeVisibleState(targetCount: newVisibleCopy.count)
            return
        }

        Task { @MainActor [missing, newVisibleCopy, visibleIDs, token] in
            let newFingerprints = await Task.detached(priority: .userInitiated) {
                Self.buildFingerprints(from: missing)
            }.value
            guard token == refreshGeneration else { return }

            var merged = pruneFingerprints(fingerprintCache, keepingOnly: visibleIDs)
            for (id, fp) in newFingerprints {
                if merged[id] == nil {
                    merged[id] = fp
                }
            }
            fingerprintCache = merged
            visibleMessages = newVisibleCopy
            finalizeVisibleState(targetCount: newVisibleCopy.count)
        }
    }

    private func pruneFingerprints(_ cache: [UUID: ContentFingerprint], keepingOnly visibleIDs: Set<UUID>) -> [UUID: ContentFingerprint] {
        var out: [UUID: ContentFingerprint] = [:]
        out.reserveCapacity(min(cache.count, visibleIDs.count))
        for id in visibleIDs {
            if let fp = cache[id] {
                out[id] = fp
            }
        }
        return out
    }

    private func finalizeVisibleState(targetCount: Int) {
        let sessionID = viewModel.chatSession.id
        let shouldReport = (targetCount != lastReportedVisibleCount) || (sessionID != lastReportedSessionID)
        lastReportedVisibleCount = targetCount
        if shouldReport {
            lastReportedSessionID = sessionID
            onMessagesCountChange(targetCount)
        }
    }

    private func prewarmThinkParts(for snapshots: [(UUID, String)]) {
        let enriched = snapshots.compactMap { entry -> (UUID, String, ContentFingerprint)? in
            guard let fp = fingerprintCache[entry.0] else { return nil }
            return (entry.0, entry.1, fp)
        }
        guard !enriched.isEmpty else { return }

        Task.detached(priority: .utility) {
            MessageRenderCache.shared.prewarmThinkParts(enriched)
        }
    }

    private func applyContentFingerprintUpdate(_ update: ChatViewModel.MessageContentUpdate) {
        if hydrationTask != nil || isHydratingSession {
            pendingRefreshAfterHydration = true
        }
        fingerprintCache[update.messageID] = update.fingerprint
    }

    nonisolated private static func buildFingerprints(from snapshots: [(UUID, String)]) -> [UUID: ContentFingerprint] {
        var map: [UUID: ContentFingerprint] = [:]
        map.reserveCapacity(snapshots.count)
        for snap in snapshots {
            map[snap.0] = ContentFingerprint.make(snap.1)
        }
        return map
    }

    private func updateContentHeightIfNeeded(_ newHeight: CGFloat) {
        let cleaned = max(0, newHeight)
        if abs(cleaned - contentHeight) > 0.5 {
            contentHeight = cleaned
            updateScrollToBottomVisibility()
        }
    }

    private func updateViewportHeightIfNeeded(_ newHeight: CGFloat) {
        let cleaned = max(0, newHeight)
        if abs(cleaned - viewportHeight) > 0.5 {
            viewportHeight = cleaned
            updateScrollToBottomVisibility()
        }
    }

    private func updateBottomAnchorIfNeeded(_ newValue: CGFloat) {
        if abs(newValue - bottomAnchorMaxY) > 0.5 {
            bottomAnchorMaxY = newValue
            updateScrollToBottomVisibility()
        }
    }

    private func updateEditingBannerHeightIfNeeded(_ newHeight: CGFloat) {
        let cleaned = max(0, newHeight)
        if abs(cleaned - editingBannerHeight) > 0.5 {
            editingBannerHeight = cleaned
        }
    }

    var body: some View {
        chatViewContent
    }

    private var chatViewContent: some View {
        dropEnabledChatView
    }

    private var layoutDecoratedChatView: some View {
        mainChatLayout
            .modifier(ChatViewPlatformTitleModifier(title: viewModel.chatSession.title))
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    composerShadowShelf

                    VStack(spacing: 12) {
                        if showScrollToBottomButton {
                            scrollToBottomButton
                                .transition(
                                    .move(edge: .bottom)
                                        .combined(with: .opacity)
                                )
                        }

                        floatingInputPanel
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, composerBottomPadding)
                }
            }
            .overlay(alignment: .bottom) {
                if !errorCenter.notices.isEmpty {
                    ErrorNoticeStack(
                        notices: errorCenter.notices,
                        onDismiss: { notice in
                            errorCenter.dismiss(notice)
                        }
                    )
                    .padding(.bottom, noticeBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(0)
                }
            }
    }

    private var lifecycleManagedChatView: some View {
        layoutDecoratedChatView
#if os(iOS) || os(tvOS)
            .ignoresSafeArea(.container, edges: .bottom)
            .ignoresSafeArea(.keyboard, edges: .bottom)
#endif
            .onPreferenceChange(EditingBannerHeightKey.self, perform: updateEditingBannerHeightIfNeeded)
            .onAppear {
                refreshVisibleMessages(hydrating: true)
#if os(macOS)
                registerReturnKeyMonitor()
#endif
            }
            .onDisappear {
#if os(macOS)
                unregisterReturnKeyMonitor()
#endif
                hydrationTask?.cancel()
                hydrationTask = nil
                isHydratingSession = false
                pendingRefreshAfterHydration = false
                expectAssistantResponseHaptics = false
                didTriggerResponseStartHaptic = false
#if os(iOS) || os(macOS)
                for task in imageImportTasks.values {
                    task.cancel()
                }
                imageImportTasks.removeAll()
                ChatImageQuickLookSupport.cleanupTemporaryPreviewURL(pendingPreviewFileURL)
                pendingPreviewFileURL = nil
#endif
            }
    }

    private var presentationManagedChatView: some View {
        lifecycleManagedChatView
#if os(iOS) || os(tvOS)
            .fullScreenCover(isPresented: $showFullScreenComposer) {
                FullScreenComposer(text: $viewModel.userMessage) {
                    isInputFocused = true
                }
            }
#endif
#if os(iOS)
            .fullScreenCover(item: $textSelectionSheetItem) { item in
                TextSelectionSheet(text: item.text)
            }
#else
            .sheet(item: $textSelectionSheetItem) { item in
                TextSelectionSheet(text: item.text)
            }
#endif
#if os(iOS) || os(macOS)
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $pickedPhotoItems,
                maxSelectionCount: max(1, remainingPendingImageAttachmentSlots),
                matching: .images
            )
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true,
                onCompletion: importSelectedImageFiles
            )
            .onChange(of: pickedPhotoItems) { _, newItems in
                importPickedPhotoItems(newItems)
            }
            .quickLookPreview($pendingPreviewFileURL)
            .onChange(of: pendingPreviewFileURL) { oldValue, newValue in
                guard oldValue != newValue else { return }
                ChatImageQuickLookSupport.cleanupTemporaryPreviewURL(oldValue)
            }
#endif
    }

    private var messageContentObservedChatView: some View {
        presentationManagedChatView
            .onReceive(viewModel.messageContentDidChange) { update in
                applyContentFingerprintUpdate(update)
                guard textHapticsEnabled else { return }
                guard expectAssistantResponseHaptics, !didTriggerResponseStartHaptic else { return }
                if let message = viewModel.chatSession.messages.first(where: { $0.id == update.messageID }),
                   !message.isUser {
                    didTriggerResponseStartHaptic = true
                    triggerTextHaptic(.selection)
                }
            }
    }

    private var branchObservedChatView: some View {
        messageContentObservedChatView
            .onReceive(viewModel.branchDidChange) {
                branchRenderEpoch &+= 1
                refreshVisibleMessages()
            }
    }

    private var loadingObservedChatView: some View {
        branchObservedChatView
            .onChange(of: viewModel.isLoading) { oldValue, newValue in
                guard oldValue, !newValue else { return }
                guard expectAssistantResponseHaptics else { return }
                guard textHapticsEnabled else {
                    expectAssistantResponseHaptics = false
                    didTriggerResponseStartHaptic = false
                    return
                }

                defer {
                    expectAssistantResponseHaptics = false
                    didTriggerResponseStartHaptic = false
                }

                let finishReason = viewModel
                    .orderedMessagesCached()
                    .last(where: { !$0.isUser })?
                    .finishReason

                switch finishReason {
                case "completed":
                    if didTriggerResponseStartHaptic {
                        triggerTextHaptic(.successStrong)
                    } else {
                        triggerTextHaptic(.success)
                    }
                case "error":
                    triggerTextHaptic(.error)
                default:
                    break
                }
            }
    }

    private var sessionObservedChatView: some View {
        loadingObservedChatView
            .onChange(of: viewModel.chatSession.id) { _, _ in
                MessageRenderCache.shared.clear()
                expectAssistantResponseHaptics = false
                didTriggerResponseStartHaptic = false
                refreshVisibleMessages(hydrating: true)
            }
            .onChange(of: viewModel.chatSession.messages.count) { _, _ in
                refreshVisibleMessages()
            }
            .onChange(of: viewModel.editingBaseMessageID) { _, _ in
                refreshVisibleMessages()
            }
    }

    private var visibleCountObservedChatView: some View {
        sessionObservedChatView
            .onChange(of: visibleMessages.count) { _, _ in
                if !showScrollToBottomButton {
                    scrollToBottom()
                }
            }
    }

    private var alertManagedChatView: some View {
        visibleCountObservedChatView
            .alert("Other activity is still running",
                   isPresented: $showStartVoiceModeInterruptAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Continue", role: .destructive) {
                    interruptAllActivitiesForVoiceModeStart()
                    startRealtimeVoiceOverlay()
                }
            } message: {
                Text("There are other tasks still running. Continuing will interrupt them and start voice mode.")
            }
            .alert("Current model does not support image input",
                   isPresented: $showUnsupportedImageSendAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Continue", role: .destructive) {
                    if !performSend(ignoringUnsupportedImageInputs: true) {
                        errorCenter.publish(
                            title: NSLocalizedString("Nothing to send", comment: "Shown when sending is skipped because no text remains after removing unsupported image inputs"),
                            message: NSLocalizedString("All selected images were ignored because this model only accepts text input.", comment: "Shown when selected images are dropped for a text-only model"),
                            category: .textModel
                        )
                    }
                }
            } message: {
                Text("This conversation contains images, but the selected model only accepts text. Continue to ignore all images in this request and send text only.")
            }
    }

    private var dropEnabledChatView: some View {
        alertManagedChatView
#if os(iOS) || os(macOS)
            .contentShape(Rectangle())
            .overlay {
                fullChatImageDropOverlay
            }
            .onDrop(
                of: acceptedImageDropTypeIdentifiers,
                delegate: ImageAttachmentDropDelegate(
                    isEnabled: currentModelSupportsImageInput,
                    isTargeted: $isImageDropTargeted,
                    suppressionState: $imageDropSuppressionState,
                    acceptedTypeIdentifiers: acceptedImageDropTypeIdentifiers,
                    filterProviders: { $0.filter(Self.itemProviderMayContainImage) },
                    importProviders: importDroppedImageProviders
                )
            )
#endif
    }

    private var mainChatLayout: some View {
        ZStack(alignment: .top) {

            VStack(spacing: 0) {
                Divider().overlay(ChatTheme.separator).opacity(0)

                // Conversation content area
                Group {
                    if isHydratingSession {
                        hydrationMaskView
                    } else if !voiceOverlayVM.isPresented {
                        GeometryReader { outerGeo in
                            ScrollViewReader { proxy in
                                ScrollView {
                                    messageList(scrollTargetsEnabled: true)
                                }
                                .coordinateSpace(name: "ChatScroll")
                                .background(
                                    Color.clear.preference(key: ViewportHeightKey.self, value: outerGeo.size.height)
                                )
                                .onPreferenceChange(ContentHeightKey.self, perform: updateContentHeightIfNeeded)
                                .onPreferenceChange(ViewportHeightKey.self, perform: updateViewportHeightIfNeeded)
                                .onPreferenceChange(BottomAnchorKey.self, perform: updateBottomAnchorIfNeeded)
                                .defaultScrollAnchor(shouldAnchorBottom ? .bottom : .top)
                                .scrollDismissesKeyboard(.interactively)
                                .onTapGesture { isInputFocused = false }
                                .onChange(of: outerGeo.size.width) { _, newWidth in
                                    updateAvailableMessageWidth(newWidth)
                                }
                                .onAppear {
                                    updateAvailableMessageWidth(outerGeo.size.width)
                                    scrollProxy = proxy
                                    DispatchQueue.main.async {
                                        scrollToBottom(animated: false)
                                    }
                                }
                            }
                        }
                    } else {
                        // Placeholder to avoid rendering work while the overlay is visible.
                        Color.clear.frame(height: 1)
                    }
                }

            }

            if shouldDisplayAudioPlayer {
                VStack {
                    AudioPlayerView()
                        .environmentObject(audioManager)
                    Spacer()
                }
                .transition(
                    .asymmetric(
                        insertion: .offset(y: -18)
                            .combined(with: .scale(scale: 0.96, anchor: .top))
                            .combined(with: .opacity),
                        removal: .offset(y: -10)
                            .combined(with: .scale(scale: 0.985, anchor: .top))
                            .combined(with: .opacity)
                    )
                )
                .zIndex(1)
                .animation(.audioPlayerVisibility, value: shouldDisplayAudioPlayer)
            }
        }
    }

#if os(iOS) || os(macOS)
    @ViewBuilder
    private var fullChatImageDropOverlay: some View {
        if isImageDropTargeted && currentModelSupportsImageInput {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(ChatTheme.accent.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(ChatTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                }
                .padding(12)
                .overlay {
                    Label("Drop images anywhere to attach", systemImage: "photo.badge.plus")
                        .font(.headline)
                        .foregroundStyle(ChatTheme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                }
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
#endif

    private var hasOtherActivityForVoiceModeStart: Bool {
        let hasText = chatSessionsViewModel.hasActiveTextRequests
        let hasVoice = audioManager.isRealtimeMode
            || audioManager.isLoading
            || audioManager.isAudioPlaying
            || !audioManager.dataTasks.isEmpty
        return hasText || hasVoice
    }

    private var textHapticsEnabled: Bool {
        !voiceOverlayVM.isPresented
    }

    private func triggerTextHaptic(_ event: AppHapticEvent) {
        guard textHapticsEnabled else { return }
        AppHaptics.trigger(event)
    }

    @discardableResult
    private func sendIfPossible() -> Bool {
        guard canSendDraft, !viewModel.isLoading else { return false }
        if viewModel.shouldWarnAboutUnsupportedImageInputBeforeSending() {
            showUnsupportedImageSendAlert = true
            return false
        }
        return performSend(ignoringUnsupportedImageInputs: false)
    }

    @discardableResult
    private func performSend(ignoringUnsupportedImageInputs: Bool) -> Bool {
        expectAssistantResponseHaptics = true
        didTriggerResponseStartHaptic = false
        guard viewModel.sendMessage(ignoringUnsupportedImageInputs: ignoringUnsupportedImageInputs) else {
            expectAssistantResponseHaptics = false
            didTriggerResponseStartHaptic = false
            return false
        }
        triggerTextHaptic(.lightTap)
        return true
    }

    private func interruptAllActivitiesForVoiceModeStart() {
        chatSessionsViewModel.cancelAllActiveTextRequests()
        if audioManager.isRealtimeMode
            || audioManager.isLoading
            || audioManager.isAudioPlaying
            || !audioManager.dataTasks.isEmpty {
            audioManager.closeAudioPlayer()
        }
    }

    private func handleOverflowChange(_ overflow: Bool) {
        let shouldShowEditorExpander = overflow
        if shouldShowEditorExpander != inputOverflow {
            DispatchQueue.main.async {
                inputOverflow = shouldShowEditorExpander
            }
        }
    }

#if os(macOS)
    private func registerReturnKeyMonitor() {
        guard returnKeyMonitor == nil else { return }
        returnKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleMacReturnKey(event)
        }
    }

    private func unregisterReturnKeyMonitor() {
        if let monitor = returnKeyMonitor {
            NSEvent.removeMonitor(monitor)
            returnKeyMonitor = nil
        }
    }

    private func handleMacReturnKey(_ event: NSEvent) -> NSEvent? {
        let returnKeyCodes: Set<UInt16> = [36, 76]
        guard returnKeyCodes.contains(event.keyCode) else { return event }
        guard isInputFocused else { return event }

        let modifierMask = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let blockingMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        if modifierMask.intersection(blockingMask).isEmpty {
            sendIfPossible()
            return nil
        }

        return event
    }
#endif

    private var floatingInputPanel: some View {
        VStack(spacing: 0) {
            if viewModel.isEditing {
                editingAccessory
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !viewModel.pendingImageAttachments.isEmpty {
                pendingAttachmentStrip
                    .padding(.top, 8)
                    .padding(.horizontal, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            composerInputRow
                .padding(.vertical, composerOuterVerticalPadding)
                .padding(.leading, 10)
                .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(PlatformColor.systemBackground.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(ChatTheme.subtleStroke.opacity(0.35), lineWidth: 0.75)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .blur(radius: 26)
                .opacity(0.82)
                .padding(.horizontal, -18)
                .frame(height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                        .blur(radius: 10)
                        .blendMode(.plusLighter)
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.16)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .blur(radius: 14)
                )
                .offset(y: 16)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 12)
        .shadow(color: Color.black.opacity(0.1), radius: 14, x: 10, y: 12)
        .shadow(color: Color.black.opacity(0.1), radius: 14, x: -10, y: 12)
        .shadow(color: Color.black.opacity(0.14), radius: 26, x: 0, y: 28)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isEditing)
    }

    private var composerInputRow: some View {
        HStack(alignment: .center, spacing: 10) {
            composerAttachmentButton

            ZStack(alignment: .topLeading) {
                if viewModel.userMessage.isEmpty {
                    Text("Type your message...")
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                        .padding(.top, InputMetrics.outerV + InputMetrics.innerTop)
                        .padding(.leading, InputMetrics.outerH + InputMetrics.innerLeading)
                        .accessibilityHint("Message field placeholder")
                }

                AutoSizingTextEditor(
                    text: $viewModel.userMessage,
                    height: $textFieldHeight,
                    maxLines: platformMaxLines(),
                    allowsImagePasting: currentModelSupportsImageInput,
                    maxPastedImages: remainingPendingImageAttachmentSlots,
                    onOverflowChange: handleOverflowChange,
                    onPasteImages: importPastedImages
                )
                .focused($isInputFocused)
                .frame(height: textFieldHeight)
                .padding(.vertical, InputMetrics.outerV)
                .padding(.leading, InputMetrics.outerH)
                .padding(.trailing, 6)

                #if os(iOS) || os(tvOS)
                if inputOverflow {
                    Button {
                        showFullScreenComposer = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                    .padding(.trailing, 8)
                    .accessibilityLabel("Open full screen editor")
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
                #endif
            }
            .frame(maxWidth: .infinity)

            floatingTrailingButton
        }
    }

    @ViewBuilder
    private var composerAttachmentButton: some View {
#if os(iOS) || os(macOS)
        if currentModelSupportsImageInput {
            Menu {
                Button {
                    guard remainingPendingImageAttachmentSlots > 0 else {
                        presentImageAttachmentLimitNotice()
                        return
                    }
                    showPhotoPicker = true
                } label: {
                    Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                }

                Button {
                    guard remainingPendingImageAttachmentSlots > 0 else {
                        presentImageAttachmentLimitNotice()
                        return
                    }
                    showFileImporter = true
                } label: {
                    Label("Choose Files", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ChatTheme.accent)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add image"))
        }
#endif
    }

    private var pendingAttachmentStrip: some View {
        ChatImageAttachmentStrip(
            attachments: viewModel.pendingImageAttachments,
            removable: true,
            maxItemSize: 72,
            onPreview: { attachment in
#if os(iOS) || os(macOS)
                presentPendingAttachmentPreview(attachment)
#endif
            },
            onRemove: { attachment in
                viewModel.removePendingImageAttachment(id: attachment.id)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editingAccessory: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.orange)
                    .frame(width: 3, height: 18)

                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("Editing")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    viewModel.cancelEditing()
                    isInputFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel editing and restore the conversation")
                .help("Cancel editing and restore the conversation")
            }
            .padding(.top, 10)
            .padding(.bottom, 8)
            .padding(.horizontal, 12)

            Divider()
                .overlay(ChatTheme.separator.opacity(0.65))
                .padding(.leading, 12)
                .padding(.trailing, 12)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: EditingBannerHeightKey.self, value: proxy.size.height)
            }
        )
    }

    private var floatingTrailingButton: some View {
        Group {
            if viewModel.isLoading {
                Button {
                    expectAssistantResponseHaptics = false
                    didTriggerResponseStartHaptic = false
                    viewModel.cancelCurrentRequest()
                    triggerTextHaptic(.warning)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Stop Generation")
                }
                .buttonStyle(.plain)
            } else if canSendDraft {
                Button {
                    sendIfPossible()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ChatTheme.accent)
                        .accessibilityLabel("Send Message")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    openRealtimeVoiceOverlay()
                } label: {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ChatTheme.accent)
                        .accessibilityLabel("Start Realtime Voice Conversation")
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 38, height: 38)
    }

    private var scrollToBottomButton: some View {
        Button {
            scrollToBottom()
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: scrollButtonSize, height: scrollButtonSize)
                .contentShape(Circle())
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .stroke(ChatTheme.subtleStroke.opacity(0.5), lineWidth: 0.6)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("Scroll to bottom")
    }

    private var scrollButtonSize: CGFloat {
        #if os(iOS) || os(tvOS)
        return 40
        #else
        return 34
        #endif
    }

    @ViewBuilder
    private var composerShadowShelf: some View {
        #if os(iOS) || os(tvOS)
        let shadowColor = Color.black.opacity(0.18)
        LinearGradient(
            colors: [
                shadowColor,
                shadowColor.opacity(0.08),
                .clear
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(maxWidth: .infinity)
        .frame(height: composerBottomPadding + 16)
        .allowsHitTesting(false)
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private func messageList(scrollTargetsEnabled: Bool) -> some View {
        let content = messageListCore()
            .padding(.horizontal, messageListHorizontalPadding)
            .padding(.top, 12)
            .frame(maxWidth: contentColumnMaxWidth(availableWidth: availableMessageWidth))
            .frame(maxWidth: .infinity, alignment: .center)

        if scrollTargetsEnabled {
            content.scrollTargetLayout()
        } else {
            content
        }
    }

    @ViewBuilder
    private func messageListCore() -> some View {
        let branchControlsEnabled = !(viewModel.isLoading || viewModel.isPriming || viewModel.isEditing)
        let developerModeEnabled = settingsManager.developerModeEnabled
        let visibleMessageIDs = visibleMessages.map(\.id)

        VStack(spacing: 12) {
            ForEach(visibleMessages, id: \.id) { (message: ChatMessage) in
                // Hide action buttons only for the assistant message that is actively streaming.
                // Using "last visible message" can briefly hide buttons on the previous assistant
                // reply while a new user message is being appended.
                let isStreamingAssistant = viewModel.isLoading && !message.isUser && message.isActive
                let showButtons = !isStreamingAssistant

                // Skip re-rendering when the message content and state have not changed.
                let fingerprint = fingerprintCache[message.id] ?? ContentFingerprint.make(message.content)
                let key = VoiceMessageEqKey(
                    id: message.id,
                    isUser: message.isUser,
                    isActive: message.isActive,
                    imageAttachmentsFP: message.imageAttachmentsFingerprint,
                    branchRenderEpoch: branchRenderEpoch,
                    showActionButtons: showButtons,
                    branchControlsEnabled: branchControlsEnabled,
                    contentFP: fingerprint,
                    developerModeEnabled: developerModeEnabled
                )

                EquatableRender(value: key) {
                    VoiceMessageView(
                        message: message,
                        showActionButtons: showButtons,
                        branchControlsEnabled: branchControlsEnabled,
                        developerModeEnabled: developerModeEnabled,
                        maxBubbleWidth: availableMessageWidth,
                        contentFingerprint: fingerprint,
                        onSelectText: { showSelectTextSheet(with: $0) },
                        onRegenerate: {
                            expectAssistantResponseHaptics = true
                            didTriggerResponseStartHaptic = false
                            viewModel.regenerateSystemMessage($0)
                            triggerTextHaptic(.lightTap)
                        },
                        onEditUserMessage: { msg in
                            viewModel.beginEditUserMessage(msg)
                            isInputFocused = true
                        },
                        onSwitchVersion: {
                            viewModel.switchToMessageVersion($0)
                        },
                        onRetry: { errMsg in
                            expectAssistantResponseHaptics = true
                            didTriggerResponseStartHaptic = false
                            viewModel.retry(afterErrorMessage: errMsg)
                            triggerTextHaptic(.lightTap)
                        }
                    )
                }
                .id(message.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if viewModel.isRetrying {
                AssistantAlignedRetryingBubble(
                    attempt: viewModel.retryAttempt,
                    lastError: viewModel.retryLastError,
                    maxBubbleWidth: availableMessageWidth
                )
            } else if viewModel.isPriming {
                AssistantAlignedLoadingBubble(maxBubbleWidth: availableMessageWidth)
            }

            Color.clear
                .frame(height: messageListBottomInset)
                .id(ScrollTarget.bottom)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BottomAnchorKey.self, value: proxy.frame(in: .named("ChatScroll")).maxY)
                    }
                )
        }
        .background(
            GeometryReader { contentGeo in
                Color.clear.preference(key: ContentHeightKey.self, value: contentGeo.size.height)
            }
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: visibleMessageIDs)
    }

    private func scrollToBottom(animated: Bool = true) {
        guard let proxy = scrollProxy else { return }
        let action = {
            proxy.scrollTo(ScrollTarget.bottom, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
        }
    }

    private func updateScrollToBottomVisibility() {
        guard viewportHeight > 0 else {
            if showScrollToBottomButton {
                showScrollToBottomButton = false
            }
            return
        }

        let bottomDistance = max(0, bottomAnchorMaxY - viewportHeight)
        let shouldShow = bottomDistance > 24
        if shouldShow != showScrollToBottomButton {
            withAnimation(.easeInOut(duration: 0.2)) {
                showScrollToBottomButton = shouldShow
            }
        }
    }

    private func updateAvailableMessageWidth(_ width: CGFloat) {
        let cleanedWidth = max(width, 0)
        guard abs(cleanedWidth - availableMessageWidth) > 0.5 else { return }
        availableMessageWidth = cleanedWidth
    }

    private func showSelectTextSheet(with text: String) {
        let selectionText = text
        guard !selectionText.isEmpty else { return }

        // Presenting a sheet directly from a context menu action is unreliable; schedule for next run loop.
        DispatchQueue.main.async {
            textSelectionSheetItem = TextSelectionSheetItem(text: selectionText)
        }
    }

#if os(iOS) || os(macOS)
    private var acceptedImageDropTypeIdentifiers: [String] {
        [UTType.image.identifier, UTType.fileURL.identifier]
    }

    private func presentPendingAttachmentPreview(_ attachment: ChatImageAttachment) {
        let previous = pendingPreviewFileURL
        pendingPreviewFileURL = ChatImageQuickLookSupport.prepareTemporaryPreviewURL(for: attachment)
        if previous != pendingPreviewFileURL {
            ChatImageQuickLookSupport.cleanupTemporaryPreviewURL(previous)
        }
    }

    private func importPickedPhotoItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let remainingSlots = remainingPendingImageAttachmentSlots
        guard remainingSlots > 0 else {
            pickedPhotoItems.removeAll()
            presentImageAttachmentLimitNotice()
            return
        }
        if items.count > remainingSlots {
            presentImageAttachmentOverflowNotice(remainingSlots: remainingSlots)
        }
        let snapshot = Array(items.prefix(remainingSlots))
        startImageImport(source: .photoPicker, cancelsEarlierPhotoImports: true) {
            limit in
            await Self.loadImageAttachments(from: snapshot, limit: limit)
        }
    }

    private func importSelectedImageFiles(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard currentModelSupportsImageInput else { return }
            guard !urls.isEmpty else { return }
            let remainingSlots = remainingPendingImageAttachmentSlots
            guard remainingSlots > 0 else {
                presentImageAttachmentLimitNotice()
                return
            }
            if urls.count > remainingSlots {
                presentImageAttachmentOverflowNotice(remainingSlots: remainingSlots)
            }
            let limitedURLs = Array(urls.prefix(remainingSlots))
            startImageImport {
                limit in
                await Self.loadImageAttachments(fromFileURLs: limitedURLs, limit: limit)
            }
        case .failure(let error):
            guard !Self.isUserCancelledImageImport(error) else { return }
            errorCenter.publish(
                title: NSLocalizedString("Image Import Failed", comment: "Title shown when importing selected image files fails"),
                message: error.localizedDescription,
                category: .textModel
            )
        }
    }

    private func importDroppedImageProviders(_ providers: [NSItemProvider]) {
        guard currentModelSupportsImageInput else { return }
        guard !providers.isEmpty else { return }
        let remainingSlots = remainingPendingImageAttachmentSlots
        guard remainingSlots > 0 else {
            presentImageAttachmentLimitNotice()
            return
        }
        if providers.count > remainingSlots {
            presentImageAttachmentOverflowNotice(remainingSlots: remainingSlots)
        }
        let limitedProviders = Array(providers.prefix(remainingSlots))
        startImageImport {
            limit in
            await Self.loadImageAttachments(fromItemProviders: limitedProviders, limit: limit)
        }
    }

    private func importPastedImages(_ payloads: [(data: Data, mimeType: String?)]) {
        guard currentModelSupportsImageInput else { return }
        if payloads.count > remainingPendingImageAttachmentSlots {
            presentImageAttachmentOverflowNotice(remainingSlots: remainingPendingImageAttachmentSlots)
        }
        let importPayloads = payloads.map { payload in
            ImageImportPayload(data: payload.data, mimeType: payload.mimeType)
        }
        startImageImport {
            await Self.loadImageAttachments(from: importPayloads, limit: $0)
        }
    }

    private func startImageImport(
        source: ImageImportSource = .other,
        cancelsEarlierPhotoImports: Bool = false,
        _ loader: @escaping (Int) async -> [ChatImageAttachment]
    ) {
        let importLimit = remainingPendingImageAttachmentSlots
        guard importLimit > 0 else {
            if source == .photoPicker {
                pickedPhotoItems.removeAll()
                activePhotoImportID = nil
            }
            return
        }

        let importID = UUID()
        if cancelsEarlierPhotoImports, let activePhotoImportID {
            imageImportTasks[activePhotoImportID]?.cancel()
            imageImportTasks[activePhotoImportID] = nil
        }

        let task = Task(priority: .utility) {
            let imported = await loader(importLimit)
            guard !Task.isCancelled else {
                await MainActor.run {
                    if activePhotoImportID == importID {
                        activePhotoImportID = nil
                    }
                    imageImportTasks[importID] = nil
                }
                return
            }
            await MainActor.run {
                if source == .photoPicker, activePhotoImportID != importID {
                    imageImportTasks[importID] = nil
                    return
                }
                guard currentModelSupportsImageInput else {
                    if source == .photoPicker {
                        pickedPhotoItems.removeAll()
                        activePhotoImportID = nil
                    }
                    imageImportTasks[importID] = nil
                    return
                }
                appendPendingImageAttachments(imported)
                if source == .photoPicker {
                    pickedPhotoItems.removeAll()
                    activePhotoImportID = nil
                }
                imageImportTasks[importID] = nil
            }
        }
        imageImportTasks[importID] = task
        if source == .photoPicker {
            activePhotoImportID = importID
        }
    }

    private func appendPendingImageAttachments(_ attachments: [ChatImageAttachment]) {
        guard !attachments.isEmpty else { return }
        let remainingSlots = max(0, Self.maxPendingImageAttachments - viewModel.pendingImageAttachments.count)
        guard remainingSlots > 0 else {
            presentImageAttachmentLimitNotice()
            return
        }
        if attachments.count > remainingSlots {
            presentImageAttachmentOverflowNotice(remainingSlots: remainingSlots)
        }

        let limitedAttachments = Array(attachments.prefix(remainingSlots))
        guard !limitedAttachments.isEmpty else { return }

        viewModel.pendingImageAttachments.append(contentsOf: limitedAttachments)
        isInputFocused = true
    }

    private var remainingPendingImageAttachmentSlots: Int {
        max(0, Self.maxPendingImageAttachments - viewModel.pendingImageAttachments.count)
    }

    private func presentImageAttachmentLimitNotice() {
        errorCenter.publish(
            title: NSLocalizedString("Too Many Images", comment: "Title shown when no more image attachments can be added"),
            message: String(
                format: NSLocalizedString(
                    "A message can include up to %lld image attachments.",
                    comment: "Shown when the user reaches the per-message image attachment cap"
                ),
                Int64(Self.maxPendingImageAttachments)
            ),
            category: .textModel
        )
    }

    private func presentImageAttachmentOverflowNotice(remainingSlots: Int) {
        guard remainingSlots > 0 else {
            presentImageAttachmentLimitNotice()
            return
        }

        errorCenter.publish(
            title: NSLocalizedString("Too Many Images", comment: "Title shown when the user imports more images than the current draft can accept"),
            message: String(
                format: NSLocalizedString(
                    "This message can include %lld additional image attachments. Extra images were ignored.",
                    comment: "Shown when imported images exceed the remaining attachment slots in the current draft"
                ),
                Int64(remainingSlots)
            ),
            category: .textModel
        )
    }

    nonisolated private static func loadImageAttachments(from items: [PhotosPickerItem], limit: Int) async -> [ChatImageAttachment] {
        guard limit > 0 else { return [] }
        var imported: [ChatImageAttachment] = []
        imported.reserveCapacity(min(items.count, limit))

        for item in items {
            guard !Task.isCancelled else { return imported }
            guard imported.count < limit else { return imported }
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { continue }

            let mimeType = preferredImageMIMEType(for: item, data: data)
            guard let attachment = await makeImageAttachmentAsync(data: data, mimeTypeHint: mimeType) else { continue }
            imported.append(attachment)
        }

        return imported
    }

    nonisolated private static func loadImageAttachments(fromFileURLs urls: [URL], limit: Int) async -> [ChatImageAttachment] {
        guard limit > 0 else { return [] }
        let worker = Task.detached(priority: .utility) {
            var imported: [ChatImageAttachment] = []
            imported.reserveCapacity(min(urls.count, limit))

            for url in urls {
                guard !Task.isCancelled else { return imported }
                guard imported.count < limit else { return imported }
                guard let attachment = await loadImageAttachmentAsync(fromFileURL: url) else { continue }
                imported.append(attachment)
            }

            return imported
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated private static func loadImageAttachments(from payloads: [ImageImportPayload], limit: Int) async -> [ChatImageAttachment] {
        guard limit > 0 else { return [] }
        let worker = Task.detached(priority: .utility) {
            var imported: [ChatImageAttachment] = []
            imported.reserveCapacity(min(payloads.count, limit))

            for payload in payloads {
                guard !Task.isCancelled else { return imported }
                guard imported.count < limit else { return imported }
                guard let attachment = await makeImageAttachmentAsync(data: payload.data, mimeTypeHint: payload.mimeType) else {
                    continue
                }
                imported.append(attachment)
            }

            return imported
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func loadImageAttachments(fromItemProviders providers: [NSItemProvider], limit: Int) async -> [ChatImageAttachment] {
        guard limit > 0 else { return [] }
        var imported: [ChatImageAttachment] = []
        imported.reserveCapacity(min(providers.count, limit))

        for provider in providers {
            guard !Task.isCancelled else { return imported }
            guard imported.count < limit else { return imported }
            guard let attachment = await loadImageAttachment(from: provider) else { continue }
            imported.append(attachment)
        }

        return imported
    }

    private static func loadImageAttachment(from provider: NSItemProvider) async -> ChatImageAttachment? {
        let imageType = provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first(where: { $0.conforms(to: .image) })

        if let imageType,
           let data = try? await provider.loadDataRepresentationAsync(forTypeIdentifier: imageType.identifier) {
            return await makeImageAttachmentAsync(data: data, mimeTypeHint: imageType.preferredMIMEType)
        }

        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
              let url = try? await provider.loadFileURLAsync() else {
            return nil
        }

        return await loadImageAttachmentAsync(fromFileURL: url)
    }

    nonisolated private static func itemProviderMayContainImage(_ provider: NSItemProvider) -> Bool {
        let registeredTypes = provider.registeredTypeIdentifiers.compactMap(UTType.init)
        if registeredTypes.contains(where: { $0.conforms(to: .image) }) {
            return true
        }

        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return false
        }

        guard let suggestedName = provider.suggestedName,
              !suggestedName.isEmpty else {
            return true
        }

        let pathExtension = URL(fileURLWithPath: suggestedName).pathExtension
        guard !pathExtension.isEmpty,
              let suggestedType = UTType(filenameExtension: pathExtension) else {
            return false
        }

        return suggestedType.conforms(to: .image)
    }

    nonisolated private static func loadImageAttachment(fromFileURL url: URL) -> ChatImageAttachment? {
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        if let contentType, !contentType.conforms(to: .image) {
            return nil
        }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        if contentType == nil, sniffedImageMIMEType(from: data) == nil {
            return nil
        }
        return makeImageAttachment(data: data, mimeTypeHint: contentType?.preferredMIMEType)
    }

    nonisolated private static func loadImageAttachmentAsync(fromFileURL url: URL) async -> ChatImageAttachment? {
        await withCheckedContinuation { continuation in
            imageProcessingQueue.async {
                continuation.resume(returning: loadImageAttachment(fromFileURL: url))
            }
        }
    }

    nonisolated private static func makeImageAttachmentAsync(data: Data, mimeTypeHint: String?) async -> ChatImageAttachment? {
        await withCheckedContinuation { continuation in
            imageProcessingQueue.async {
                continuation.resume(returning: makeImageAttachment(data: data, mimeTypeHint: mimeTypeHint))
            }
        }
    }

    nonisolated private static func makeImageAttachment(data: Data, mimeTypeHint: String?) -> ChatImageAttachment? {
        guard !data.isEmpty else { return nil }
        let resolvedMIMEType = sniffedImageMIMEType(from: data)
            ?? canonicalImageMIMEType(mimeTypeHint ?? "")

        if shouldTranscodeToCompatibleFormat(resolvedMIMEType),
           let transcodedPayload = transcodeToCompatibleImagePayload(from: data) {
            return ChatImageAttachment(mimeType: transcodedPayload.mimeType, data: transcodedPayload.data)
        }

        return ChatImageAttachment(mimeType: resolvedMIMEType, data: data)
    }

    nonisolated private static func canonicalImageMIMEType(_ mimeType: String) -> String {
        let normalized = mimeType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch normalized {
        case "image/jpg":
            return "image/jpeg"
        default:
            return normalized.isEmpty ? "image/jpeg" : normalized
        }
    }

    nonisolated private static func isUserCancelledImageImport(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return true
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlyingError.domain == NSCocoaErrorDomain && underlyingError.code == NSUserCancelledError
        }

        return false
    }

    nonisolated private static func shouldTranscodeToCompatibleFormat(_ mimeType: String) -> Bool {
        canonicalImageMIMEType(mimeType) != "image/jpeg"
    }

    nonisolated private static func transcodeToCompatibleImagePayload(from data: Data) -> (data: Data, mimeType: String)? {
        #if os(macOS)
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let outputImage = cgImageUsesTransparency(cgImage) ? opaqueJPEGReadyImage(from: cgImage) ?? cgImage : cgImage
        let bitmap = NSBitmapImageRep(cgImage: outputImage)
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 0.9]
        guard let jpegData = bitmap.representation(using: .jpeg, properties: properties) else {
            return nil
        }
        return (jpegData, "image/jpeg")
        #else
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            return nil
        }

        let outputImage = cgImageUsesTransparency(cgImage) ? opaqueJPEGReadyImage(from: cgImage) ?? cgImage : cgImage
        let renderedImage = UIImage(cgImage: outputImage, scale: image.scale, orientation: image.imageOrientation)
        guard let jpegData = renderedImage.jpegData(compressionQuality: 0.9) else {
            return nil
        }
        return (jpegData, "image/jpeg")
        #endif
    }

    nonisolated private static func cgImageUsesTransparency(_ image: CGImage) -> Bool {
        let alphaInfo = image.alphaInfo
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            break
        default:
            return false
        }

        guard let alphaOffset = alphaComponentOffset(in: image, alphaInfo: alphaInfo) else {
            return true
        }
        guard let provider = image.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return true
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel > alphaOffset, image.height > 0, image.width > 0 else {
            return true
        }

        for row in 0..<image.height {
            let rowStart = row * image.bytesPerRow
            for column in 0..<image.width {
                let alphaIndex = rowStart + (column * bytesPerPixel) + alphaOffset
                if bytes[alphaIndex] < UInt8.max {
                    return true
                }
            }
        }

        return false
    }

    nonisolated private static func alphaComponentOffset(in image: CGImage, alphaInfo: CGImageAlphaInfo) -> Int? {
        switch alphaInfo {
        case .alphaOnly:
            return 0
        case .first, .premultipliedFirst:
            return image.bitmapInfo.contains(.byteOrder32Little) ? 3 : 0
        case .last, .premultipliedLast:
            return image.bitmapInfo.contains(.byteOrder32Little) ? 0 : 3
        default:
            return nil
        }
    }

    nonisolated private static func opaqueJPEGReadyImage(from image: CGImage) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    nonisolated private static func preferredImageMIMEType(for item: PhotosPickerItem, data: Data) -> String {
        if let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }),
           let mime = type.preferredMIMEType {
            return canonicalImageMIMEType(mime)
        }
        return inferredMIMEType(from: data)
    }

    nonisolated private static func inferredMIMEType(from data: Data) -> String {
        sniffedImageMIMEType(from: data) ?? "image/jpeg"
    }

    nonisolated private static func sniffedImageMIMEType(from data: Data) -> String? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if data.starts(with: [0x49, 0x49, 0x2A, 0x00]) || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "image/tiff"
        }
        if data.starts(with: [0x42, 0x4D]) { return "image/bmp" }

        if data.count >= 12 {
            let marker = String(decoding: data[4..<12], as: UTF8.self).lowercased()
            if marker.contains("heic") || marker.contains("heif") {
                return "image/heic"
            }
            if marker.contains("webp") {
                return "image/webp"
            }
        }

        return nil
    }
#endif

    private func openRealtimeVoiceOverlay() {
        guard !voiceOverlayVM.isPresented else { return }
        if hasOtherActivityForVoiceModeStart {
            showStartVoiceModeInterruptAlert = true
            return
        }
        startRealtimeVoiceOverlay()
    }

    private func startRealtimeVoiceOverlay() {
        guard !voiceOverlayVM.isPresented else { return }
        AppHaptics.trigger(.selection)
        expectAssistantResponseHaptics = false
        didTriggerResponseStartHaptic = false
        voiceOverlayVM.presentSession(chatViewModel: viewModel) { text in
            viewModel.prepareRealtimeTTSForNextAssistant()
            viewModel.userMessage = text
            expectAssistantResponseHaptics = false
            didTriggerResponseStartHaptic = false
            _ = sendIfPossible()
        }
    }

    private var hydrationMaskView: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    let session = ChatSession()
    let speechManager = SpeechInputManager()
    let overlayVM = VoiceChatOverlayViewModel(
        speechInputManager: speechManager,
        audioManager: GlobalAudioManager.shared,
        errorCenter: AppErrorCenter.shared,
        settingsManager: SettingsManager.shared,
        reachabilityMonitor: ServerReachabilityMonitor.shared
    )

    ChatView(viewModel: ChatViewModel(chatSession: session))
        .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
        .environmentObject(GlobalAudioManager.shared)
        .environmentObject(SettingsManager.shared)
        .environmentObject(ChatSessionsViewModel())
        .environmentObject(speechManager)
        .environmentObject(overlayVM)
        .environmentObject(AppErrorCenter.shared)
}
