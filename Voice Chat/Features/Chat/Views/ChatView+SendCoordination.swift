//
//  ChatView+SendCoordination.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/14.
//

import SwiftUI

extension ChatView {
    var sendCoordinator: ChatSendCoordinator {
        ChatSendCoordinator(
            viewModel: viewModel,
            chatSessionsViewModel: chatSessionsViewModel,
            audioManager: audioManager,
            errorCenter: errorCenter,
            voiceOverlayVM: voiceOverlayVM,
            imageImportDriver: imageImportDriver,
            focusInput: { isInputFocused = true },
            setActiveAlert: { activeAlert = $0 },
            setResponseHapticState: { expectsAssistantResponse, didTriggerResponseStart in
                expectAssistantResponseHaptics = expectsAssistantResponse
                didTriggerResponseStartHaptic = didTriggerResponseStart
            },
            requestScrollToBottomAfterSend: requestScrollToBottomAfterSend,
            cancelScrollToBottomAfterSend: cancelScrollToBottomAfterSend,
            triggerTextHaptic: triggerTextHaptic(_:)
        )
    }
}
