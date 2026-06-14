//
//  RealtimeVoiceChatSession.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/13.
//

import Combine

@MainActor
protocol RealtimeVoiceChatSession: AnyObject {
    var supportsRealtimeVoiceImageInput: Bool { get }
    var isRealtimeVoiceChatLoading: Bool { get }
    var isRealtimeVoiceChatPriming: Bool { get }
    var realtimeVoiceRequestFailurePublisher: AnyPublisher<String, Never> { get }
    var realtimeVoiceContentProgressPublisher: AnyPublisher<Void, Never> { get }
    var realtimeVoiceRetryProgressPublisher: AnyPublisher<Int, Never> { get }

    func cancelRealtimeVoiceRequest()
}
