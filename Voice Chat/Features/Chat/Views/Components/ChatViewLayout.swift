//
//  ChatViewLayout.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct ChatConversationLayout<MessageList: View, HydrationMask: View>: View {
    @ObservedObject var audioManager: GlobalAudioManager

    let navigationTitle: String
    let isInitialContentReady: Bool
    let isVoiceOverlayPresented: Bool
    let shouldDisplayAudioPlayer: Bool
    let messageList: () -> MessageList
    let hydrationMask: () -> HydrationMask
    let onContentHeightChange: (CGFloat) -> Void
    let onViewportHeightChange: (CGFloat) -> Void
    let onBottomAnchorChange: (CGFloat) -> Void
    let onDismissKeyboard: () -> Void
    let onWidthChange: (CGFloat) -> Void
    let onScrollProxyReady: (ScrollViewProxy, CGFloat) -> Void

    var body: some View {
        conversationContent
            .overlay(alignment: .top) {
                if shouldDisplayAudioPlayer {
                    audioPlayerOverlay
                }
            }
    }

    @ViewBuilder
    private var conversationContent: some View {
        if !isVoiceOverlayPresented {
            ZStack {
                scrollView
                    .opacity(isInitialContentReady ? 1 : 0)
                    .offset(
                        y: isInitialContentReady
                            ? 0
                            : ChatScrollContentMotion.hiddenOffset
                    )
                    .scaleEffect(
                        isInitialContentReady
                            ? 1
                            : ChatScrollContentMotion.hiddenScale,
                        anchor: .bottom
                    )
                    .allowsHitTesting(isInitialContentReady)

                if !isInitialContentReady {
                    hydrationMask()
                        .allowsHitTesting(false)
                }
            }
            .animation(
                ChatScrollContentMotion.animation,
                value: isInitialContentReady
            )
            .modifier(ChatViewPlatformTitleModifier(title: navigationTitle))
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(ChatViewPlatformTitleModifier(title: navigationTitle))
        }
    }

    private var scrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                messageList()
            }
            .coordinateSpace(name: "ChatScroll")
            .background(
                GeometryReader { outerGeo in
                    Color.clear
                        .preference(key: ViewportHeightKey.self, value: outerGeo.size.height)
                        .onChange(of: outerGeo.size.width) { _, newWidth in
                            onWidthChange(newWidth)
                        }
                        .onAppear {
                            onWidthChange(outerGeo.size.width)
                            onScrollProxyReady(proxy, outerGeo.size.width)
                        }
                }
            )
            .onPreferenceChange(ContentHeightKey.self, perform: onContentHeightChange)
            .onPreferenceChange(ViewportHeightKey.self, perform: onViewportHeightChange)
            .onPreferenceChange(BottomAnchorKey.self, perform: onBottomAnchorChange)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .defaultScrollAnchor(.top, for: .alignment)
            #if os(iOS) || os(tvOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onTapGesture(perform: onDismissKeyboard)
        }
    }

    private var audioPlayerOverlay: some View {
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

struct ChatViewChromeModifier<Composer: View, ScrollButton: View, ShadowShelf: View>: ViewModifier {
    @State private var noticeStackHeight: CGFloat = 0

    let layoutMetrics: ChatComposerLayoutMetrics
    let availableMessageWidth: CGFloat
    let showScrollToBottomButton: Bool
    let notices: [AppErrorNotice]
    let onDismissNotice: (AppErrorNotice) -> Void
    let composer: () -> Composer
    let scrollToBottomButton: () -> ScrollButton
    let shadowShelf: () -> ShadowShelf

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                noticesOverlay
            }
            .overlay(alignment: .bottom) {
                scrollToBottomOverlay
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomChrome
            }
            .onPreferenceChange(FloatingNoticeStackHeightKey.self) { newHeight in
                let cleaned = max(0, newHeight)
                if abs(cleaned - noticeStackHeight) > 0.5 {
                    noticeStackHeight = cleaned
                }
            }
    }

    private var bottomChrome: some View {
        ZStack(alignment: .bottom) {
            shadowShelf()

            VStack(spacing: 12) {
                composer()
                    .frame(maxWidth: composerPanelMaxWidth(availableWidth: availableMessageWidth))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, layoutMetrics.floatingPanelHorizontalInset)
            .padding(.bottom, layoutMetrics.composerBottomPadding)
        }
    }

    @ViewBuilder
    private var noticesOverlay: some View {
        noticesView
            .frame(maxWidth: composerPanelMaxWidth(availableWidth: availableMessageWidth))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, layoutMetrics.floatingPanelHorizontalInset)
            .padding(.bottom, floatingControlsBottomPadding)
            .animation(floatingControlAnimation, value: noticeIDs)
            .zIndex(1)
    }

    @ViewBuilder
    private var scrollToBottomOverlay: some View {
        ZStack(alignment: .bottom) {
            if showScrollToBottomButton {
                scrollToBottomButton()
                    .padding(.bottom, scrollToBottomOverlayBottomPadding)
                    .transition(floatingControlTransition)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, layoutMetrics.floatingPanelHorizontalInset)
        .animation(floatingControlAnimation, value: showScrollToBottomButton)
        .zIndex(2)
    }

    private var scrollToBottomOverlayBottomPadding: CGFloat {
        floatingControlsBottomPadding
            + noticeStackHeight
            + (notices.isEmpty ? 0 : 12)
    }

    private var floatingControlsBottomPadding: CGFloat {
        12
    }

    private var floatingControlTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 44)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.98, anchor: .bottom)),
            removal: .offset(y: 28)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .bottom))
        )
    }

    private var floatingControlAnimation: Animation {
        .spring(response: 0.32, dampingFraction: 0.9)
    }

    private var noticeIDs: [UUID] {
        notices.map(\.id)
    }

    @ViewBuilder
    private var noticesView: some View {
        if !notices.isEmpty {
            ErrorNoticeStack(
                notices: notices,
                onDismiss: onDismissNotice,
                maxWidth: composerPanelMaxWidth(availableWidth: availableMessageWidth),
                edgePadding: 0
            )
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: FloatingNoticeStackHeightKey.self,
                        value: proxy.size.height
                    )
                }
            )
            .transition(floatingControlTransition)
            .zIndex(0)
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                .preference(key: FloatingNoticeStackHeightKey.self, value: 0)
        }
    }
}

struct ChatComposerShadowShelf: View {
    var body: some View {
        EmptyView()
    }
}

struct ChatViewLifecycleModifier: ViewModifier {
    @Binding var editingBannerHeight: CGFloat

    let onAppear: () -> Void
    let onDisappear: () -> Void

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(EditingBannerHeightKey.self) { newHeight in
                assignHeight(newHeight, to: $editingBannerHeight)
            }
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
    }

    private func assignHeight(_ newHeight: CGFloat, to binding: Binding<CGFloat>) {
        let cleaned = max(0, newHeight)
        if abs(cleaned - binding.wrappedValue) > 0.5 {
            binding.wrappedValue = cleaned
        }
    }
}

struct ChatViewObservationModifier: ViewModifier {
    @ObservedObject var viewModel: ChatViewModel

    @Binding var branchRenderEpoch: Int
    @Binding var textFieldHeight: CGFloat
    @Binding var inputOverflow: Bool
    @Binding var expectAssistantResponseHaptics: Bool
    @Binding var didTriggerResponseStartHaptic: Bool

    let textHapticsEnabled: Bool
    let searchNavigationTarget: ChatSearchNavigationTarget?
    let visibleMessageCount: Int
    let isInitialContentReady: Bool
    let triggerTextHaptic: (AppHapticEvent) -> Void
    let onMessageContentUpdate: (ChatViewModel.MessageContentUpdate) -> Void
    let onVisibleMessagesNeedRefresh: () -> Void
    let onSessionTransition: () -> Void
    let onBranchTransition: () -> Void
    let onSearchNavigationTargetChange: (ChatSearchNavigationTarget?) -> Void
    let onVisibleMessageCountChange: () -> Void
    let onInitialContentReady: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(viewModel.messageContentDidChange, perform: handleMessageContentUpdate)
            .onReceive(viewModel.branchDidChange) {
                branchRenderEpoch &+= 1
                onBranchTransition()
            }
            .onChange(of: viewModel.isLoading, initial: false, handleLoadingChange)
            .onChange(of: viewModel.chatSession.id) { _, _ in
                MessageRenderCache.shared.clear()
                resetResponseHaptics()
                textFieldHeight = InputMetrics.defaultHeight
                inputOverflow = false
                onSessionTransition()
            }
            .onChange(of: viewModel.chatSession.messages.count) { _, _ in
                onVisibleMessagesNeedRefresh()
            }
            .onChange(of: viewModel.editingBaseMessageID) { _, _ in
                onVisibleMessagesNeedRefresh()
            }
            .onChange(of: searchNavigationTarget) { _, newTarget in
                onSearchNavigationTargetChange(newTarget)
            }
            .onChange(of: visibleMessageCount) { _, _ in
                onVisibleMessageCountChange()
            }
            .onChange(of: isInitialContentReady) { _, isReady in
                if isReady {
                    onInitialContentReady()
                }
            }
    }

    private func handleMessageContentUpdate(_ update: ChatViewModel.MessageContentUpdate) {
        onMessageContentUpdate(update)
        guard textHapticsEnabled else { return }
        guard expectAssistantResponseHaptics, !didTriggerResponseStartHaptic else { return }
        if let message = viewModel.chatSession.messages.first(where: { $0.id == update.messageID }),
           !message.isUser {
            didTriggerResponseStartHaptic = true
            triggerTextHaptic(.selection)
        }
    }

    private func handleLoadingChange(_ oldValue: Bool, _ newValue: Bool) {
        guard oldValue, !newValue else { return }
        guard expectAssistantResponseHaptics else { return }
        guard textHapticsEnabled else {
            resetResponseHaptics()
            return
        }

        defer {
            resetResponseHaptics()
        }

        let finishReason = viewModel
            .orderedMessagesCached()
            .last(where: { !$0.isUser })?
            .finishReason

        switch finishReason {
        case "completed":
            triggerTextHaptic(didTriggerResponseStartHaptic ? .successStrong : .success)
        case "error":
            triggerTextHaptic(.error)
        default:
            break
        }
    }

    private func resetResponseHaptics() {
        expectAssistantResponseHaptics = false
        didTriggerResponseStartHaptic = false
    }
}

#if os(iOS) || os(macOS) || os(visionOS)
struct ChatImageDropModifier: ViewModifier {
    @ObservedObject var imageImportDriver: ChatImageAttachmentImportDriver

    let supportsImageInput: Bool
    let viewModel: ChatViewModel
    let errorCenter: AppErrorCenter
    let focusInput: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay {
                ChatImageDropOverlay(isPresented: imageImportDriver.isDropTargeted && supportsImageInput)
            }
            .onDrop(
                of: imageImportDriver.acceptedDropTypeIdentifiers,
                delegate: ImageAttachmentDropDelegate(
                    isEnabled: supportsImageInput,
                    isTargeted: $imageImportDriver.isDropTargeted,
                    suppressionState: $imageImportDriver.dropSuppressionState,
                    acceptedTypeIdentifiers: imageImportDriver.acceptedDropTypeIdentifiers,
                    filterProviders: { $0.filter(ChatImageAttachmentImporter.itemProviderMayContainImage) },
                    importProviders: importProviders
                )
            )
    }

    private func importProviders(_ providers: [NSItemProvider]) {
        imageImportDriver.importDroppedImageProviders(
            providers,
            viewModel: viewModel,
            errorCenter: errorCenter,
            focusInput: focusInput
        )
    }
}

struct ChatImageDropOverlay: View {
    let isPresented: Bool

    var body: some View {
        if isPresented {
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
                        .appChromedContainer(
                            cornerRadius: 999,
                            tint: ChatTheme.accent.opacity(0.12),
                            shadowOpacity: 0.28
                        )
                }
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}
#endif
