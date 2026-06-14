//
//  ChatViewModel+RealtimeVoiceChatSession.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/13.
//

import Combine

extension ChatViewModel: RealtimeVoiceChatSession {
    var supportsRealtimeVoiceImageInput: Bool {
        currentModelSupportsImageInput()
    }

    var isRealtimeVoiceChatLoading: Bool {
        isLoading
    }

    var isRealtimeVoiceChatPriming: Bool {
        isPriming
    }

    var realtimeVoiceRequestFailurePublisher: AnyPublisher<String, Never> {
        requestDidFail.eraseToAnyPublisher()
    }

    var realtimeVoiceContentProgressPublisher: AnyPublisher<Void, Never> {
        messageContentDidChange
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    var realtimeVoiceRetryProgressPublisher: AnyPublisher<Int, Never> {
        $retryAttempt.eraseToAnyPublisher()
    }

    func cancelRealtimeVoiceRequest() {
        cancelCurrentRequest()
    }
}
