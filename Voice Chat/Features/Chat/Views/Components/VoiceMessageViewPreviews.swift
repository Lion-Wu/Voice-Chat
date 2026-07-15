//
//  VoiceMessageViewPreviews.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

#Preview {
    let message: ChatMessage = {
        let session = ChatSession(title: "Preview")
        let message = ChatMessage(
            content: "<think>\nReasoning preview...\n</think>\nHello from the assistant!",
            isUser: false,
            isActive: false,
            createdAt: Date(),
            deltaCount: 1,
            characterCount: 0,
            session: session
        )
        session.messages.append(message)
        return message
    }()
    let audio = GlobalAudioManager()

    VoiceMessageView(
        message: message,
        showActionButtons: true,
        branchControlsEnabled: true,
        developerModeEnabled: true,
        contentFingerprint: ContentFingerprint.make(message.content),
        onSelectText: { _ in },
        onRegenerate: { _ in },
        onEditUserMessage: { _ in },
        onSwitchVersion: { _ in },
        onRetry: { _ in }
    )
    .environmentObject(audio)
    .modelContainer(for: [ChatSession.self, ChatMessage.self, ChatRequestContextMetadata.self, AppSettings.self], inMemory: true)
    .padding()
    .background(AppBackgroundView())
}
