//
//  ChatViewModel+RealtimeVoiceChatSession.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/13.
//

import Combine
import Foundation

extension ChatViewModel: RealtimeVoiceChatSession {
    var supportsRealtimeVoiceImageInput: Bool {
        currentModelSupportsImageInput()
    }

    var isRealtimeVoiceChatLoading: Bool {
        isLoading || isToolContinuationLoading
    }

    var isRealtimeVoiceChatPriming: Bool {
        isPriming
    }

    var realtimeVoiceAssistantSnapshot: RealtimeVoiceAssistantSnapshot? {
        makeRealtimeVoiceAssistantSnapshot()
    }

    private func makeRealtimeVoiceAssistantSnapshot(
        messageID: UUID? = nil,
        contentFingerprint: ContentFingerprint? = nil
    ) -> RealtimeVoiceAssistantSnapshot? {
        let messages = orderedMessagesCached()
        guard let message = messages.last, !message.isUser else {
            return nil
        }
        if let messageID, message.id != messageID {
            return nil
        }
        let placements = realtimeVoiceToolActivityPlacements(for: message)
        return RealtimeVoiceAssistantSnapshot(
            messageID: message.id,
            contentFingerprint: contentFingerprint ?? ContentFingerprint.make(message.renderFingerprintSource),
            toolActivities: realtimeVoiceToolActivities(for: message, placements: placements),
            toolActivityPlacements: placements,
            isStreaming: isLoading && message.isActive
        )
    }

    var realtimeVoiceLoadingStatePublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest3(
            $isLoading.removeDuplicates(),
            $isPriming.removeDuplicates(),
            $isToolContinuationLoading.removeDuplicates()
        )
        .map { $0 || $1 || $2 }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    var realtimeVoiceRequestFailurePublisher: AnyPublisher<String, Never> {
        requestDidFail.eraseToAnyPublisher()
    }

    var realtimeVoiceContentProgressPublisher: AnyPublisher<RealtimeVoiceAssistantSnapshot, Never> {
        messageContentDidChange
            .compactMap { [weak self] update in
                self?.makeRealtimeVoiceAssistantSnapshot(
                    messageID: update.messageID,
                    contentFingerprint: update.fingerprint
                )
            }
            .eraseToAnyPublisher()
    }

    var realtimeVoiceRetryProgressPublisher: AnyPublisher<Int, Never> {
        $retryAttempt.eraseToAnyPublisher()
    }

    func cancelRealtimeVoiceRequest() {
        cancelCurrentRequest()
    }

    func resolveRealtimeVoiceToolAuthorization(requestID: String, allowed: Bool) {
        resolveToolAuthorization(requestID: requestID, allowed: allowed)
    }

    private func realtimeVoiceToolActivityPlacements(for message: ChatMessage) -> [ChatToolActivityPlacement] {
        var merged = message.toolActivityPlacements
        for placement in messageToolActivityPlacements[message.id] ?? [] {
            if let index = merged.firstIndex(where: { $0.id == placement.id }) {
                merged[index] = placement
            } else {
                merged.append(placement)
            }
        }
        return merged
    }

    private func realtimeVoiceToolActivities(
        for message: ChatMessage,
        placements: [ChatToolActivityPlacement]
    ) -> [ChatToolActivity] {
        var activities = message.toolActivityPlacements.map(\.activity)
        for activity in messageToolActivities[message.id] ?? [] {
            if let index = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[index] = activity
            } else {
                activities.append(activity)
            }
        }

        var placementOrder: [String: Int] = [:]
        for (index, placement) in placements.enumerated() where placementOrder[placement.id] == nil {
            placementOrder[placement.id] = index
        }
        return activities.sorted {
            let lhs = placementOrder[$0.id] ?? Int.max
            let rhs = placementOrder[$1.id] ?? Int.max
            if lhs == rhs {
                return $0.id < $1.id
            }
            return lhs < rhs
        }
    }
}
