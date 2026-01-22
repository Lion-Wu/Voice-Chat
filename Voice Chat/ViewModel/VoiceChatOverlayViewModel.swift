//
//  VoiceChatOverlayViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class VoiceChatOverlayViewModel: ObservableObject {

    enum OverlayState: Equatable {
        case listening
        case loading
        case speaking
        case error(String)
    }

    @Published var isPresented: Bool = false
    @Published private(set) var state: OverlayState = .listening
    @Published var selectedLanguage: SpeechInputManager.DictationLanguage
    @Published private(set) var showErrorBanner: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var outputLevel: Double = 0

    var availableLanguages: [SpeechInputManager.DictationLanguage] {
        SpeechInputManager.DictationLanguage.allCases
    }

    private let speechInputManager: SpeechInputManager
    private let audioManager: GlobalAudioManager
    private let errorCenter: AppErrorCenter
    private var cancellables: Set<AnyCancellable> = []
    private var onRecognizedFinal: ((String) -> Void)?
    private weak var activeChatViewModel: ChatViewModel?
    private var autoResumeEnabled = false
    private var isStartingRecording = false
    private let overlayAnimation = Animation.spring(response: 0.4, dampingFraction: 0.85)

    init(
        speechInputManager: SpeechInputManager,
        audioManager: GlobalAudioManager,
        errorCenter: AppErrorCenter
    ) {
        self.speechInputManager = speechInputManager
        self.audioManager = audioManager
        self.errorCenter = errorCenter
        self.selectedLanguage = speechInputManager.currentLanguage
        bindState()
    }

    func presentSession(chatViewModel: ChatViewModel? = nil, onFinal: @escaping (String) -> Void) {
        activeChatViewModel = chatViewModel
        onRecognizedFinal = onFinal
        autoResumeEnabled = true
        showErrorBanner = false
        errorMessage = nil
        withAnimation(overlayAnimation) {
            isPresented = true
        }
        state = .listening
        startListening()
    }

    func dismiss() {
        interruptActiveWorkOnDismiss()
        autoResumeEnabled = false
        withAnimation(overlayAnimation) {
            isPresented = false
        }
        state = .listening
        showErrorBanner = false
        errorMessage = nil
        cleanupSession()
        activeChatViewModel = nil
    }

    func handleViewDisappear() {
        cleanupSession()
    }

    func dismissErrorMessage() {
        showErrorBanner = false
    }

    func updateLanguage(_ language: SpeechInputManager.DictationLanguage) {
        guard selectedLanguage != language else { return }
        // Defer the publish to avoid mutating @Published properties during view updates.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.selectedLanguage = language
            self.speechInputManager.currentLanguage = language
            if self.isPresented {
                self.restartListening()
            }
        }
    }

    // MARK: - Internal bindings

    private func bindState() {
        speechInputManager.$inputLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.inputLevel = level
            }
            .store(in: &cancellables)

        audioManager.$outputLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.outputLevel = Double(level)
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

        speechInputManager.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                guard let message = error, !message.isEmpty else { return }
                self?.handleError(message)
            }
            .store(in: &cancellables)
    }

    // MARK: - State transitions

    private func startListening() {
        guard autoResumeEnabled else { return }
        guard !speechInputManager.isRecording else { return }
        guard !isStartingRecording else { return }

        isStartingRecording = true
        Task { [weak self] in
            guard let self else { return }
            await self.startRecordingSession()
            await MainActor.run {
                self.isStartingRecording = false
            }
        }
    }

    private func restartListening() {
        cleanupRecordingOnly()
        startListening()
    }

    private func startRecordingSession() async {
        await speechInputManager.startRecording(
            language: selectedLanguage,
            onPartial: { _ in },
            onFinal: { [weak self] text in
                guard let self else { return }
                self.state = .loading
                self.onRecognizedFinal?(text)
            }
        )
        if let error = speechInputManager.lastError, !error.isEmpty {
            handleError(error)
        }
    }

    private func cleanupRecordingOnly() {
        speechInputManager.stopRecording()
    }

    private func cleanupSession() {
        onRecognizedFinal = nil
        cleanupRecordingOnly()
    }

    private func interruptActiveWorkOnDismiss() {
        activeChatViewModel?.cancelCurrentRequest()

        let hasVoiceWork = audioManager.isRealtimeMode
            || audioManager.isLoading
            || audioManager.isAudioPlaying
            || !audioManager.dataTasks.isEmpty

        if hasVoiceWork {
            audioManager.closeAudioPlayer()
        }
    }

    private func handleRecordingChange(_ isRecording: Bool) {
        if isRecording {
            state = .listening
        } else {
            resumeListeningIfIdle()
        }
    }

    private func handleAudioPlayingChange(_ playing: Bool) {
        if playing {
            state = .speaking
        } else {
            resumeListeningIfIdle()
        }
    }

    private func handleAudioLoadingChange(_ loading: Bool) {
        if loading, !audioManager.isAudioPlaying {
            state = .loading
        } else {
            resumeListeningIfIdle()
        }
    }

    private func resumeListeningIfIdle() {
        guard autoResumeEnabled, isPresented else { return }
        guard !audioManager.isAudioPlaying else { return }
        guard !audioManager.isLoading else { return }
        guard !speechInputManager.isRecording else { return }
        startListening()
    }

    private func handleError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = trimmed
        showErrorBanner = true
        state = .error(message)
        autoResumeEnabled = false
        pushRealtimeVoiceError(trimmed)
    }

    private func pushRealtimeVoiceError(_ message: String) {
        guard !message.isEmpty else { return }
        errorCenter.publish(
            title: NSLocalizedString("Realtime voice unavailable", comment: "Shown when realtime voice dictation/playback encounters an error"),
            message: message,
            category: .realtimeVoice,
            autoDismiss: 12
        )
    }
}
