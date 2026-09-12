//
//  RealtimeVoiceChatSession.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/13.
//

import Combine
import Foundation

struct RealtimeVoiceAssistantSnapshot {
    let messageID: UUID
    let contentFingerprint: ContentFingerprint
    let toolActivities: [ChatToolActivity]
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let isStreaming: Bool

    var isWaitingForToolAuthorization: Bool {
        toolActivities.contains { $0.phase == .authorizing }
            || toolActivityPlacements.contains { $0.activity.phase == .authorizing }
    }
}

struct RealtimeVoiceTextRetryStatus: Equatable, Sendable {
    let isRetrying: Bool
    let attempt: Int
    let lastError: String?
}

@MainActor
protocol RealtimeVoiceChatSession: AnyObject {
    var supportsRealtimeVoiceImageInput: Bool { get }
    var isRealtimeVoiceChatLoading: Bool { get }
    var isRealtimeVoiceChatPriming: Bool { get }
    var realtimeVoiceAssistantSnapshot: RealtimeVoiceAssistantSnapshot? { get }
    var realtimeVoiceLoadingStatePublisher: AnyPublisher<Bool, Never> { get }
    var realtimeVoiceRequestFailurePublisher: AnyPublisher<String, Never> { get }
    var realtimeVoiceContentProgressPublisher: AnyPublisher<RealtimeVoiceAssistantSnapshot, Never> { get }
    var realtimeVoiceRetryStatusPublisher: AnyPublisher<RealtimeVoiceTextRetryStatus, Never> { get }
    var realtimeVoiceLongWaitNoticePublisher: AnyPublisher<ChatStreamLongWaitNotice?, Never> { get }

    func cancelRealtimeVoiceRequest()
    func retryRealtimeVoiceLongWaitingText() -> Bool
    func retryRealtimeVoiceFailedText() -> Bool
    func resolveRealtimeVoiceToolAuthorization(requestID: String, allowed: Bool)
}
