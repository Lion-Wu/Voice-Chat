//
//  VoiceChatOverlayViewModel+ErrorHandling.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension VoiceChatOverlayViewModel {
    func handleError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if case let .error(existing) = state, existing == trimmed {
            return
        }
        errorMessage = trimmed
        showErrorBanner = true
        state = .error(trimmed)
        autoResumeEnabled = false
        dismissVisionCapture()
        cancelStartTasks()
        stopLoadingWatchdog()
        cancelConnectivityTask()
        speechInputManager.setHoldToSpeakActive(false)
        cleanupRecordingOnly()

        activeChatSession?.cancelRealtimeVoiceRequest()
        closeAudioIfVoiceWorkIsActive()
        pushRealtimeVoiceError(trimmed)
    }

    func currentVoiceWorkSnapshot() -> VoiceWorkSnapshot {
        VoiceWorkSnapshot(
            audio: audioManager.audioPlaybackSnapshot,
            isChatLoading: activeChatSession?.isRealtimeVoiceChatLoading == true,
            isChatPriming: activeChatSession?.isRealtimeVoiceChatPriming == true
        )
    }

    func closeAudioIfVoiceWorkIsActive() {
        guard currentVoiceWorkSnapshot().hasVoiceWork else { return }
        audioManager.closeAudioPlayer()
    }

    func pushRealtimeVoiceError(_ message: String) {
        guard !message.isEmpty else { return }
        errorCenter.publish(
            title: NSLocalizedString("Realtime voice unavailable", comment: "Shown when realtime voice dictation/playback encounters an error"),
            message: message,
            category: .realtimeVoice,
            autoDismiss: 12
        )
    }
}
