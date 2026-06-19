//
//  VoiceChatOverlayViewModel+RecordingSession.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension VoiceChatOverlayViewModel {
    func startListening() {
        guard autoResumeEnabled else { return }
        guard isPresented else { return }
        guard !currentVoiceWorkSnapshot().blocksListeningStart else { return }
        guard !speechInputManager.isRecording else { return }
        guard !isStartingRecording else { return }

        let attemptID = recordingStartCoordinator.beginStart()
        let startTask = Task { [weak self] in
            guard let self else { return }
            await self.startRecordingSession()
            await MainActor.run {
                switch self.recordingStartCoordinator.completeStart(attemptID: attemptID) {
                case .stale, .finished:
                    break
                case .restartRequested:
                    self.restartListening()
                }
            }
        }
        recordingStartCoordinator.registerStartRecordingTask(startTask)

        let watchdogTask = Task { [weak self] in
            guard let self else { return }
            // Don't treat the permission prompt window as a hard startup failure.
            // We only start the watchdog timeout after the system permission flow resolves.
            while !Task.isCancelled {
                let snapshot = await MainActor.run { () -> (stillRelevant: Bool, isWaitingOnPermissions: Bool) in
                    guard self.recordingStartCoordinator.isActiveStartAttempt(attemptID) else { return (false, false) }
                    guard self.isPresented else { return (false, false) }
                    guard !self.speechInputManager.isRecording else { return (false, false) }
                    return (true, self.speechInputManager.isRequestingPermissions)
                }

                guard snapshot.stillRelevant else { return }
                guard snapshot.isWaitingOnPermissions else { break }

                try? await Task.sleep(for: .milliseconds(200))
            }

            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                guard self.recordingStartCoordinator.isActiveStartAttempt(attemptID) else { return }
                guard self.isPresented else { return }
                guard !self.speechInputManager.isRecording else { return }
                guard !self.speechInputManager.isRequestingPermissions else { return }
                guard self.recordingStartCoordinator.failStart(attemptID: attemptID) else { return }
                self.handleError(NSLocalizedString("Microphone is unavailable.", comment: "Shown when starting speech recognition takes too long"))
            }
        }
        recordingStartCoordinator.registerStartWatchdogTask(watchdogTask)
    }

    func restartListening() {
        if recordingStartCoordinator.requestRestartAfterStartIfNeeded() {
            return
        }
        cleanupRecordingOnly()
        startListening()
    }

    func startRecordingSession() async {
        resetVisionCaptureSpeechActivity()
        await speechInputManager.startRecording(
            language: selectedLanguage,
            onPartial: { [weak self] text in
                guard let self else { return }
                self.handleRecognizedPartial(text)
            },
            onFinal: { [weak self] text in
                guard let self else { return }
                self.handleRecognizedFinal(text)
            },
            onSpeechActivityStarted: { [weak self] in
                guard let self else { return }
                self.markVisionCaptureSpeechDetected()
            }
        )
        if let error = speechInputManager.lastError, !error.isEmpty {
            handleError(error)
        }
    }

    func handleRecognizedPartial(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        markVisionCaptureSpeechDetected()
    }

    func handleRecognizedFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        markVisionCaptureSpeechDetected()

        if isSendSuppressed {
            // User is holding the long press, so suppress automatic sending.
            return
        }

        sendRecognizedText(trimmed)
    }

    func handleListeningTap() {
        isSendSuppressed = false

        if speechInputManager.isRecording {
            speechInputManager.stopRecording()
        } else if isStartingRecording {
            // Treat a second tap as "cancel" even if the microphone hasn't finished starting yet.
            cancelStartTasks()
            speechInputManager.stopRecording(finalize: false)
        } else {
            startListening()
        }
    }

    func sendRecognizedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let visionAttachments = selectedVisionAttachmentsForCurrentUtterance()
        resetVisionCaptureSamples()
        showErrorBanner = false
        errorMessage = nil
        state = .loading
        startLoadingWatchdog()
        onRecognizedFinal?(trimmed, visionAttachments)
    }

    func cleanupRecordingOnly() {
        speechInputManager.setHoldToSpeakActive(false)
        speechInputManager.stopRecording(finalize: false)
    }

    func cleanupSession() {
        onRecognizedFinal = nil
        cancelStartTasks()
        stopLoadingWatchdog()
        cancelConnectivityTask()
        dismissVisionCapture()
        cleanupRecordingOnly()
        sessionCancellables.removeAll()
    }

    func cancelStartTasks() {
        recordingStartCoordinator.cancelStartTasks()
    }

    func startLoadingWatchdog() {
        loadingWatchdog.start(
            isActive: { [weak self] in
                self?.isPresented == true && self?.state == .loading
            },
            voiceWorkSnapshot: { [weak self] in
                self?.currentVoiceWorkSnapshot() ?? VoiceWorkSnapshot.idle
            },
            onTimeout: { [weak self] in
                self?.handleLoadingWatchdogTimeout()
            }
        )
    }

    func stopLoadingWatchdog() {
        loadingWatchdog.stop()
    }

    func markLoadingProgress() {
        guard state == .loading else { return }
        loadingWatchdog.markProgress()
    }

    func handleLoadingWatchdogTimeout() {
        activeChatSession?.cancelRealtimeVoiceRequest()
        closeAudioIfVoiceWorkIsActive()
        handleError(NSLocalizedString("Connection timed out", comment: "Shown when voice mode stalls without progress"))
    }

    func interruptActiveWorkOnDismiss() {
        activeChatSession?.cancelRealtimeVoiceRequest()
        stopLoadingWatchdog()
        closeAudioIfVoiceWorkIsActive()
    }

    func interruptActiveWorkAndRestartListening() {
        activeChatSession?.cancelRealtimeVoiceRequest()
        autoResumeEnabled = true
        cancelStartTasks()
        stopLoadingWatchdog()
        cancelConnectivityTask()
        isSendSuppressed = false
        showErrorBanner = false
        errorMessage = nil

        closeAudioIfVoiceWorkIsActive()

        state = .listening
        restartListening()
    }

    func handleRecordingChange(_ isRecording: Bool) {
        if case .error = state { return }
        if isRecording {
            beginVisionCaptureUtteranceIfNeeded()
            stopLoadingWatchdog()
            state = .listening
        } else {
            updateVisionCaptureRecordingState(isRecording: false)
            resetVisionCaptureSpeechActivity()
            resumeListeningIfIdle()
        }
    }

    func handleAudioPlayingChange(_ playing: Bool) {
        if case .error = state { return }
        if playing {
            stopLoadingWatchdog()
            state = .speaking
        } else {
            resumeListeningIfIdle()
        }
    }

    func handleAudioLoadingChange(_ loading: Bool) {
        if case .error = state { return }
        if loading, !audioManager.isAudioPlaying {
            state = .loading
            startLoadingWatchdog()
        } else {
            stopLoadingWatchdog()
            resumeListeningIfIdle()
        }
    }

    func resumeListeningIfIdle() {
        guard autoResumeEnabled, isPresented else { return }
        // Avoid restarting the microphone while we're in the middle of sending/loading a response.
        guard !loadingWatchdog.isRunning else { return }
        guard !currentVoiceWorkSnapshot().blocksAutoResume else { return }
        guard !speechInputManager.isRecording else { return }
        startListening()
    }
}
