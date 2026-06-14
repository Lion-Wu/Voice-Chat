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
        speechInputManager.$inputLevel
            .map { min(1.0, max(0.0, $0)) }
            .removeDuplicates(by: { abs($0 - $1) < 0.003 })
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.inputLevelSubject.send(level)
            }
            .store(in: &cancellables)

        audioManager.outputLevelPublisher
            .map { Double(min(1.0, max(0.0, $0))) }
            .removeDuplicates(by: { abs($0 - $1) < 0.003 })
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.outputLevelSubject.send(level)
            }
            .store(in: &cancellables)

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

        audioManager.$isAudioPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                self?.handleAudioPlayingChange(playing)
            }
            .store(in: &cancellables)

        audioManager.$isLoading
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] loading in
                self?.handleAudioLoadingChange(loading)
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
                // Keep the overlay in sync with global reachability banners so it doesn't stall in loading forever.
                if chatOK == false || ttsOK == false {
                    self.handleError(self.connectivityErrorMessage(chatOK: chatOK, ttsOK: ttsOK))
                }
            }
            .store(in: &cancellables)
    }

    func bindSession(chatSession: (any RealtimeVoiceChatSession)?) {
        sessionCancellables.removeAll()
        guard let chatSession else { return }

        chatSession.realtimeVoiceRequestFailurePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard let self else { return }
                guard self.isPresented else { return }
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.handleError(trimmed)
            }
            .store(in: &sessionCancellables)

        chatSession.realtimeVoiceContentProgressPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isPresented else { return }
                self.markLoadingProgress()
            }
            .store(in: &sessionCancellables)

        chatSession.realtimeVoiceRetryProgressPublisher
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isPresented else { return }
                self.markLoadingProgress()
            }
            .store(in: &sessionCancellables)
    }
}
