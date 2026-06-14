//
//  ChatViewPreviews.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.13.
//

import SwiftUI
import SwiftData
import Foundation

@MainActor
private func makePreviewChatSessions(
    settingsManager: SettingsManager = .shared,
    reachability: ServerReachabilityMonitor = .shared,
    audioManager: GlobalAudioManager = .shared
) -> ChatSessionsViewModel {
    ChatSessionsViewModel(
        settingsManager: settingsManager,
        reachability: reachability,
        audioManager: audioManager
    )
}

@MainActor
private func makePreviewChatViewModel(
    session: ChatSession,
    settingsManager: SettingsManager = .shared,
    reachability: ServerReachabilityMonitor = .shared,
    audioManager: GlobalAudioManager = .shared
) -> ChatViewModel {
    ChatViewModel(
        chatSession: session,
        settingsManager: settingsManager,
        reachability: reachability,
        audioManager: audioManager
    )
}

private struct ChatViewAttachmentPreviewScene: View {
    private let settingsManager: SettingsManager
    private let speechManager: SpeechInputManager
    private let overlayVM: VoiceChatOverlayViewModel
    private let session: ChatSession

    init() {
        let settingsManager = SettingsManager.shared
        settingsManager.updateChatSettings(apiURL: settingsManager.chatSettings.apiURL, selectedModel: "gpt-5")
        self.settingsManager = settingsManager

        let speechManager = SpeechInputManager()
        self.speechManager = speechManager

        self.overlayVM = VoiceChatOverlayViewModel(
            speechInputManager: speechManager,
            audioManager: GlobalAudioManager.shared,
            errorCenter: AppErrorCenter.shared,
            settingsManager: settingsManager,
            reachabilityMonitor: ServerReachabilityMonitor.shared
        )
        self.session = ChatSession()
    }

    var body: some View {
        ChatView(viewModel: makePreviewChatViewModel(session: session, settingsManager: settingsManager))
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(settingsManager)
            .environmentObject(makePreviewChatSessions(settingsManager: settingsManager))
            .environmentObject(speechManager)
            .environmentObject(overlayVM)
            .environmentObject(AppErrorCenter.shared)
    }
}

private struct ChatViewSupportingContentPreviewScene: View {
    private let settingsManager: SettingsManager
    private let speechManager: SpeechInputManager
    private let overlayVM: VoiceChatOverlayViewModel
    private let viewModel: ChatViewModel

    init() {
        let settingsManager = SettingsManager.shared
        settingsManager.updateChatSettings(apiURL: settingsManager.chatSettings.apiURL, selectedModel: "gpt-5")
        self.settingsManager = settingsManager

        let speechManager = SpeechInputManager()
        self.speechManager = speechManager

        self.overlayVM = VoiceChatOverlayViewModel(
            speechInputManager: speechManager,
            audioManager: GlobalAudioManager.shared,
            errorCenter: AppErrorCenter.shared,
            settingsManager: settingsManager,
            reachabilityMonitor: ServerReachabilityMonitor.shared
        )

        let session = ChatSession()
        let viewModel = makePreviewChatViewModel(session: session, settingsManager: settingsManager)
        viewModel.userMessage = "待发送的草稿"
        _ = viewModel.enqueueCurrentDraft()
        viewModel.pendingImageAttachments = [
            ChatImageAttachment(
                mimeType: "image/png",
                data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jW7QAAAAASUVORK5CYII=") ?? Data()
            )
        ]
        viewModel.userMessage = "正在编辑的消息"
        viewModel.editingBaseMessageID = UUID()
        self.viewModel = viewModel
    }

    var body: some View {
        ChatView(viewModel: viewModel)
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(settingsManager)
            .environmentObject(makePreviewChatSessions(settingsManager: settingsManager))
            .environmentObject(speechManager)
            .environmentObject(overlayVM)
            .environmentObject(AppErrorCenter.shared)
    }
}

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

    ChatView(viewModel: makePreviewChatViewModel(session: session))
        .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
        .environmentObject(GlobalAudioManager.shared)
        .environmentObject(SettingsManager.shared)
        .environmentObject(makePreviewChatSessions())
        .environmentObject(speechManager)
        .environmentObject(overlayVM)
        .environmentObject(AppErrorCenter.shared)
}

#Preview("Composer With Attachment", traits: .fixedLayout(width: 900, height: 240)) {
    ChatViewAttachmentPreviewScene()
}

#Preview("Composer With Supporting Content", traits: .fixedLayout(width: 900, height: 340)) {
    ChatViewSupportingContentPreviewScene()
}
