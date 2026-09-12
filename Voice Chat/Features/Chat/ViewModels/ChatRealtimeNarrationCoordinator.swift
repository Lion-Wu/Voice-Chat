//
//  ChatRealtimeNarrationCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

@MainActor
final class ChatRealtimeNarrationCoordinator {
    private let audioManager: GlobalAudioManager
    private var enableNextAssistant = false
    private var segmenter = IncrementalTextSegmenter()

    private(set) var isActive = false

    init(audioManager: GlobalAudioManager) {
        self.audioManager = audioManager
    }

    var shouldUseVoicePrompt: Bool {
        isActive || audioManager.isRealtimeMode
    }

    func prepareNextAssistant() {
        enableNextAssistant = true
    }

    func cancelPreparedAssistant() {
        enableNextAssistant = false
    }

    @discardableResult
    func startPreparedStreamIfNeeded() -> Bool {
        isActive = enableNextAssistant
        enableNextAssistant = false

        if isActive {
            segmenter.reset()
            audioManager.startRealtimeStream()
        }
        return isActive
    }

    func appendDelta(_ piece: String) {
        guard isActive else { return }
        let newSegments = segmenter.append(piece)
        appendNonEmptySegments(newSegments)
    }

    func finishActiveStream(flushingBufferedText: Bool) {
        guard isActive else { return }
        if flushingBufferedText {
            appendNonEmptySegments(segmenter.finalize())
        }
        audioManager.finishRealtimeStream()
        isActive = false
    }

    private func appendNonEmptySegments(_ segments: [String]) {
        for segment in segments where !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            audioManager.appendRealtimeSegment(segment)
        }
    }
}
