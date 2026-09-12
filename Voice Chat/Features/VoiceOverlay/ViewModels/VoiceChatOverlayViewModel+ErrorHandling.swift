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
        textServiceStatus = nil
        voiceServiceStatus = nil
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
    }

    func retryService(_ source: RealtimeVoiceServiceSource) {
        let didStart: Bool
        switch source {
        case .text:
            guard let status = textServiceStatus else { return }
            switch status.kind {
            case .longWait:
                didStart = activeChatSession?.retryRealtimeVoiceLongWaitingText() == true
            case .failed:
                didStart = activeChatSession?.retryRealtimeVoiceFailedText() == true
            case .retrying:
                return
            }
            if didStart {
                textServiceStatus = nil
            }
        case .voice:
            guard let status = voiceServiceStatus else { return }
            if case .retrying = status.kind { return }
            didStart = audioManager.retryCurrentTTSRequestIssue()
            if didStart {
                voiceServiceStatus = nil
            }
        }

        guard didStart else { return }
        if audioManager.audioPlaybackSnapshot.hasPlayableAudioRemaining || audioManager.isAudioPlaying {
            state = .speaking
        } else {
            state = .loading
        }
        reconcileVoiceWorkPresentation()
    }

    @discardableResult
    func retryPendingServices() -> Bool {
        let failedSources = serviceStatuses.compactMap { status -> RealtimeVoiceServiceSource? in
            status.kind == .failed || status.kind == .longWait ? status.source : nil
        }
        guard !failedSources.isEmpty else { return false }
        for source in failedSources {
            retryService(source)
        }
        return true
    }

    func currentVoiceWorkSnapshot() -> VoiceWorkSnapshot {
        let assistantSnapshot = activeChatSession?.realtimeVoiceAssistantSnapshot
        return VoiceWorkSnapshot(
            audio: audioManager.audioPlaybackSnapshot,
            isChatLoading: activeChatSession?.isRealtimeVoiceChatLoading == true,
            isChatPriming: activeChatSession?.isRealtimeVoiceChatPriming == true,
            isWaitingForToolAuthorization: assistantSnapshot?.isWaitingForToolAuthorization == true
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
