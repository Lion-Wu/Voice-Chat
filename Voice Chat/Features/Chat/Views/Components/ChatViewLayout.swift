//
//  ChatViewLayout.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct ChatConversationLayout<MessageList: View, HydrationMask: View>: View {
    @ObservedObject var audioManager: GlobalAudioManager

    let isHydratingSession: Bool
    let isVoiceOverlayPresented: Bool
    let shouldDisplayAudioPlayer: Bool
    let shouldUseBottomScrollAnchor: Bool
    let messageList: () -> MessageList
    let hydrationMask: () -> HydrationMask
    let onContentHeightChange: (CGFloat) -> Void
    let onViewportHeightChange: (CGFloat) -> Void
    let onBottomAnchorChange: (CGFloat) -> Void
    let onDismissKeyboard: () -> Void
    let onWidthChange: (CGFloat) -> Void
    let onScrollProxyReady: (ScrollViewProxy, CGFloat) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Divider().overlay(ChatTheme.separator).opacity(0)
                conversationContent
            }

            if shouldDisplayAudioPlayer {
                audioPlayerOverlay
            }
        }
    }

    @ViewBuilder
    private var conversationContent: some View {
        if isHydratingSession {
            hydrationMask()
        } else if !isVoiceOverlayPresented {
            GeometryReader { outerGeo in
                ScrollViewReader { proxy in
                    ScrollView {
                        messageList()
                    }
                    .coordinateSpace(name: "ChatScroll")
                    .background(
                        Color.clear.preference(key: ViewportHeightKey.self, value: outerGeo.size.height)
                    )
                    .onPreferenceChange(ContentHeightKey.self, perform: onContentHeightChange)
                    .onPreferenceChange(ViewportHeightKey.self, perform: onViewportHeightChange)
                    .onPreferenceChange(BottomAnchorKey.self, perform: onBottomAnchorChange)
                    .defaultScrollAnchor(shouldUseBottomScrollAnchor ? .bottom : .top)
                    #if os(iOS) || os(tvOS)
                    .scrollDismissesKeyboard(.interactively)
                    #endif
                    .onTapGesture(perform: onDismissKeyboard)
                    .onChange(of: outerGeo.size.width) { _, newWidth in
                        onWidthChange(newWidth)
                    }
                    .onAppear {
                        onWidthChange(outerGeo.size.width)
                        onScrollProxyReady(proxy, outerGeo.size.width)
                    }
                }
            }
        } else {
            Color.clear.frame(height: 1)
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
    let title: String
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
            .modifier(ChatViewPlatformTitleModifier(title: title))
            .overlay(alignment: .bottom) {
                composerOverlay
            }
            .overlay(alignment: .bottom) {
                noticesOverlay
            }
    }

    private var composerOverlay: some View {
        ZStack(alignment: .bottom) {
            shadowShelf()

            VStack(spacing: 12) {
                if showScrollToBottomButton {
                    scrollToBottomButton()
                        .padding(.bottom, layoutMetrics.scrollButtonNoticeClearance)
                        .transition(
                            .move(edge: .bottom)
                                .combined(with: .opacity)
                        )
                }

                composer()
                    .frame(maxWidth: composerPanelMaxWidth(availableWidth: availableMessageWidth))
                    .frame(maxWidth: .infinity)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: FloatingInputPanelHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
            }
            .padding(.horizontal, layoutMetrics.floatingPanelHorizontalInset)
            .padding(.bottom, layoutMetrics.composerBottomPadding)
        }
    }

    @ViewBuilder
    private var noticesOverlay: some View {
        if !notices.isEmpty {
            ErrorNoticeStack(
                notices: notices,
                onDismiss: onDismissNotice,
                maxWidth: composerPanelMaxWidth(availableWidth: availableMessageWidth)
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ErrorNoticeStackHeightKey.self, value: proxy.size.height)
                }
            )
            .frame(maxWidth: .infinity)
            .padding(.bottom, layoutMetrics.noticeBottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(0)
        }
    }
}

struct ChatComposerShadowShelf: View {
    let bottomPadding: CGFloat

    var body: some View {
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
        .frame(height: bottomPadding + 16)
        .allowsHitTesting(false)
        #else
        EmptyView()
        #endif
    }
}

struct ChatViewLifecycleModifier: ViewModifier {
    @Binding var editingBannerHeight: CGFloat
    @Binding var errorNoticeStackHeight: CGFloat
    @Binding var measuredFloatingInputPanelHeight: CGFloat

    let noticesAreEmpty: Bool
    let onAppear: () -> Void
    let onDisappear: () -> Void

    func body(content: Content) -> some View {
        content
            #if os(iOS) || os(tvOS)
            .ignoresSafeArea(.container, edges: .bottom)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            #endif
            .onPreferenceChange(EditingBannerHeightKey.self) { newHeight in
                assignHeight(newHeight, to: $editingBannerHeight)
            }
            .onPreferenceChange(ErrorNoticeStackHeightKey.self) { newHeight in
                assignHeight(newHeight, to: $errorNoticeStackHeight)
            }
            .onPreferenceChange(FloatingInputPanelHeightKey.self) { newHeight in
                assignHeight(newHeight, to: $measuredFloatingInputPanelHeight)
            }
            .onChange(of: noticesAreEmpty) { _, isEmpty in
                if isEmpty {
                    errorNoticeStackHeight = 0
                }
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
    let triggerTextHaptic: (AppHapticEvent) -> Void
    let onMessageContentUpdate: (ChatViewModel.MessageContentUpdate) -> Void
    let onVisibleMessagesNeedRefresh: () -> Void
    let onSessionTransition: () -> Void
    let onSearchNavigationTargetChange: (ChatSearchNavigationTarget?) -> Void
    let onVisibleMessageCountChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(viewModel.messageContentDidChange, perform: handleMessageContentUpdate)
            .onReceive(viewModel.branchDidChange) {
                branchRenderEpoch &+= 1
                onVisibleMessagesNeedRefresh()
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
