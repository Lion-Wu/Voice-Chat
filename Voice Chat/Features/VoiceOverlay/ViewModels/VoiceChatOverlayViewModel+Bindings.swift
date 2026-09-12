//
//  VoiceChatOverlayViewModel+Bindings.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Combine
import Foundation

extension VoiceChatOverlayViewModel {
    func bindState() {
        speechInputManager.$currentLanguage
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] language in
                self?.selectedLanguage = language
            }
            .store(in: &cancellables)

        speechInputManager.$isRecording
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                self?.handleRecordingChange(isRecording)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            audioManager.$isAudioPlaying.removeDuplicates(),
            audioManager.$isLoading.removeDuplicates(),
            audioManager.$isPlaybackRequested.removeDuplicates(),
            audioManager.isBufferingPublisher.removeDuplicates()
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.handleAudioActivityChange()
            }
            .store(in: &cancellables)

        audioManager.$errorMessage
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard let self else { return }
                guard self.isPresented else { return }
                guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.handleError(message)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            audioManager.$ttsRequestIssue.removeDuplicates(),
            audioManager.isRetryingPublisher.removeDuplicates(),
            audioManager.retryAttemptPublisher.removeDuplicates(),
            audioManager.retryLastErrorPublisher.removeDuplicates()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] issue, isRetrying, attempt, lastError in
            self?.handleVoiceServiceStatus(
                issue: issue,
                isRetrying: isRetrying,
                attempt: attempt,
                lastError: lastError
            )
        }
        .store(in: &cancellables)

        speechInputManager.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                guard let message = error, !message.isEmpty else { return }
                self?.handleError(message)
            }
            .store(in: &cancellables)

        reachabilityMonitor.$isChatReachable
            .removeDuplicates()
            .combineLatest(reachabilityMonitor.$isTTSReachable.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] chatOK, ttsOK in
                guard let self else { return }
                guard self.isPresented else { return }
                guard !(chatOK == true && ttsOK == true) else { return }
                // Active requests own their retry and recovery state. A periodic
                // reachability probe must not interrupt buffered speech or cancel
                // an in-flight text/TTS request.
                guard !self.currentVoiceWorkSnapshot().hasVoiceWork else { return }
                if chatOK == false || ttsOK == false {
                    self.handleError(self.connectivityErrorMessage(chatOK: chatOK, ttsOK: ttsOK))
                }
            }
            .store(in: &cancellables)
    }

    func bindSession(chatSession: (any RealtimeVoiceChatSession)?) {
        sessionCancellables.removeAll()
        guard let chatSession else { return }

        chatSession.realtimeVoiceLoadingStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isLoading in
                self?.handleChatLoadingStateChange(isLoading)
            }
            .store(in: &sessionCancellables)

        chatSession.realtimeVoiceRequestFailurePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard let self else { return }
                guard self.isPresented else { return }
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.textServiceStatus = RealtimeVoiceServiceStatus(
                    source: .text,
                    kind: .failed,
                    message: trimmed
                )
                self.reconcileVoiceWorkPresentation()
            }
            .store(in: &sessionCancellables)

        chatSession.realtimeVoiceContentProgressPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                guard self.isPresented else { return }
                self.markLoadingProgress()
                self.realtimeAssistantSnapshot = snapshot
                self.reconcileVoiceWorkPresentation()
            }
            .store(in: &sessionCancellables)

        chatSession.realtimeVoiceRetryStatusPublisher
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                guard self.isPresented else { return }
                self.markLoadingProgress()
                if status.isRetrying {
                    guard let message = status.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !message.isEmpty else {
                        return
                    }
                    self.textServiceStatus = RealtimeVoiceServiceStatus(
                        source: .text,
                        kind: .retrying(attempt: max(1, status.attempt)),
                        message: message
                    )
                } else if case .retrying? = self.textServiceStatus?.kind {
                    self.textServiceStatus = nil
                }
                self.refreshRealtimeAssistantSnapshot()
                self.reconcileVoiceWorkPresentation()
            }
            .store(in: &sessionCancellables)

        chatSession.realtimeVoiceLongWaitNoticePublisher
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] notice in
                guard let self else { return }
                guard self.isPresented else { return }
                if let notice {
                    let message: String
                    switch notice {
                    case .awaitingFirstToken:
                        message = NSLocalizedString(
                            "Connected, but the text service has not started responding. You can keep waiting or retry.",
                            comment: "Shown in realtime voice mode when text generation has no first token"
                        )
                    case .awaitingNextToken:
                        message = NSLocalizedString(
                            "Connected, but the text service has not returned anything new. You can keep waiting or retry.",
                            comment: "Shown in realtime voice mode when text generation stalls between tokens"
                        )
                    }
                    self.textServiceStatus = RealtimeVoiceServiceStatus(
                        source: .text,
                        kind: .longWait,
                        message: message
                    )
                } else if self.textServiceStatus?.kind == .longWait {
                    self.textServiceStatus = nil
                }
                self.reconcileVoiceWorkPresentation()
            }
            .store(in: &sessionCancellables)
    }

    private func handleVoiceServiceStatus(
        issue: TTSRequestIssue?,
        isRetrying: Bool,
        attempt: Int,
        lastError: String?
    ) {
        guard isPresented else { return }
        if let issue {
            voiceServiceStatus = RealtimeVoiceServiceStatus(
                source: .voice,
                kind: issue.kind == .longWait ? .longWait : .failed,
                message: issue.message
            )
        } else if isRetrying {
            guard let message = lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty else {
                return
            }
            voiceServiceStatus = RealtimeVoiceServiceStatus(
                source: .voice,
                kind: .retrying(attempt: max(1, attempt)),
                message: message
            )
        } else {
            voiceServiceStatus = nil
        }
        reconcileVoiceWorkPresentation()
    }
}
