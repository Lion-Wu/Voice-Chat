//
//  ChatView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import SwiftUI
import Foundation
import SwiftData

struct ChatView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var errorCenter: AppErrorCenter
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject var viewModel: ChatViewModel
    @State var textFieldHeight: CGFloat = InputMetrics.defaultHeight
    @State var editingBannerHeight: CGFloat = 0
    @State var availableMessageWidth: CGFloat = 680
    @FocusState var isInputFocused: Bool

    @State var textSelectionSheetItem: TextSelectionSheetItem?

    @State var inputOverflow: Bool = false
    @State var showFullScreenComposer: Bool = false

    @State var scrollState = ChatScrollState()
    @State var scrollProxy: ScrollViewProxy?
    @State var branchRenderEpoch: Int = 0
    @State var scrollInteractionState = ChatScrollInteractionState()
    @State var activeAlert: ChatAlert?
    @State var expectAssistantResponseHaptics: Bool = false
    @State var didTriggerResponseStartHaptic: Bool = false
    @StateObject var visibleMessageController = ChatVisibleMessageController()
    @StateObject var initialRenderCoordinator = ChatInitialRenderCoordinator()
#if os(iOS) || os(macOS) || os(visionOS)
    @StateObject var imageImportDriver = ChatImageAttachmentImportDriver()
#endif

#if os(macOS)
    @StateObject var returnKeySendMonitor = ChatReturnKeySendMonitor()
#endif

    // View model that coordinates the realtime voice overlay.
    @EnvironmentObject var voiceOverlayVM: VoiceChatOverlayViewModel

    var onMessagesCountChange: @MainActor @Sendable (Int) -> Void = { _ in }

    init(
        viewModel: ChatViewModel,
        onMessagesCountChange: @MainActor @Sendable @escaping (Int) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onMessagesCountChange = onMessagesCountChange
    }

}
