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
    @Published private(set) var isSendSuppressed: Bool = false

    var availableLanguages: [SpeechInputManager.DictationLanguage] {
        SpeechInputManager.DictationLanguage.allCases
    }

    private let speechInputManager: SpeechInputManager
    private let audioManager: GlobalAudioManager
    private let errorCenter: AppErrorCenter
    private let settingsManager: SettingsManager
    private let reachabilityMonitor: ServerReachabilityMonitor
    private var cancellables: Set<AnyCancellable> = []
    private var sessionCancellables: Set<AnyCancellable> = []
    private var onRecognizedFinal: ((String) -> Void)?
    private weak var activeChatViewModel: ChatViewModel?
    private var autoResumeEnabled = false
    private var isStartingRecording = false
    private var pendingRestartAfterStart: Bool = false
    private var startAttemptID: UUID?
    private var startRecordingTask: Task<Void, Never>?
    private var startWatchdogTask: Task<Void, Never>?
    private var loadingWatchdogTask: Task<Void, Never>?
    private var lastLoadingProgressAt: Date?
    private let loadingStallTimeout: TimeInterval = 60
    private let loadingStallTimeoutWithActiveAudioRequests: TimeInterval = 120
    private var connectivityTask: Task<Void, Never>?
    private var connectivityAttemptID: UUID?
    private let overlayAnimation = Animation.spring(response: 0.4, dampingFraction: 0.85)

    init(
        speechInputManager: SpeechInputManager,
        audioManager: GlobalAudioManager,
        errorCenter: AppErrorCenter,
        settingsManager: SettingsManager,
        reachabilityMonitor: ServerReachabilityMonitor
    ) {
        self.speechInputManager = speechInputManager
        self.audioManager = audioManager
        self.errorCenter = errorCenter
        self.settingsManager = settingsManager
        self.reachabilityMonitor = reachabilityMonitor
        self.selectedLanguage = speechInputManager.currentLanguage
        bindState()
    }

    func presentSession(chatViewModel: ChatViewModel? = nil, onFinal: @escaping (String) -> Void) {
        activeChatViewModel = chatViewModel
        bindSession(chatViewModel: chatViewModel)
        onRecognizedFinal = onFinal
        autoResumeEnabled = false
        isSendSuppressed = false
        showErrorBanner = false
        errorMessage = nil
        withAnimation(overlayAnimation) {
            isPresented = true
        }
        state = .loading
        beginConnectivityPreflight()
    }

    func dismiss() {
        interruptActiveWorkOnDismiss()
        autoResumeEnabled = false
        cancelStartTasks()
        stopLoadingWatchdog()
        speechInputManager.setHoldToSpeakActive(false)
        cancelConnectivityTask()
        withAnimation(overlayAnimation) {
            isPresented = false
        }
        state = .listening
        showErrorBanner = false
        errorMessage = nil
        isSendSuppressed = false
        cleanupSession()
        activeChatViewModel = nil
    }

    func handleViewDisappear() {
        cancelStartTasks()
        stopLoadingWatchdog()
        speechInputManager.setHoldToSpeakActive(false)
        cancelConnectivityTask()
        cleanupSession()
    }

    func handleCircleTap() {
        guard isPresented else { return }

        switch state {
        case .listening:
            handleListeningTap()
        case .error:
            attemptReconnect()
        case .loading:
            // Don't let a tap bypass the initial connectivity preflight.
            guard connectivityAttemptID == nil else { return }
            interruptActiveWorkAndRestartListening()
        case .speaking:
            interruptActiveWorkAndRestartListening()
        }
    }

    func handleCircleLongPressBegan() {
        guard isPresented else { return }
        guard state == .listening else { return }
        isSendSuppressed = true
        speechInputManager.setHoldToSpeakActive(true)
        if !speechInputManager.isRecording {
            startListening()
        }
    }

    func handleCircleLongPressEnded() {
        guard isPresented else { return }
        isSendSuppressed = false
        speechInputManager.setHoldToSpeakActive(false)
        if speechInputManager.isRecording {
            speechInputManager.stopRecording(finalize: true)
            return
        }

        // If the user released before the microphone finished starting, cancel the in-flight start
        // so we don't begin recording after the gesture ends.
        if isStartingRecording {
            cancelStartTasks()
            speechInputManager.stopRecording(finalize: true)
        }
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

    private func bindSession(chatViewModel: ChatViewModel?) {
        sessionCancellables.removeAll()
        guard let chatViewModel else { return }

        chatViewModel.requestDidFail
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard let self else { return }
                guard self.isPresented else { return }
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.handleError(trimmed)
            }
            .store(in: &sessionCancellables)

        chatViewModel.messageContentDidChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isPresented else { return }
                self.markLoadingProgress()
            }
            .store(in: &sessionCancellables)

        chatViewModel.$retryAttempt
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isPresented else { return }
                self.markLoadingProgress()
            }
            .store(in: &sessionCancellables)
    }

    // MARK: - State transitions

    private func beginConnectivityPreflight() {
        cancelConnectivityTask()

        let attemptID = UUID()
        connectivityAttemptID = attemptID

        connectivityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.connectivityAttemptID == attemptID {
                    self.connectivityTask = nil
                    self.connectivityAttemptID = nil
                }
            }

            await self.reachabilityMonitor.checkAll(settings: self.settingsManager)

            guard self.isPresented else { return }
            guard self.connectivityAttemptID == attemptID else { return }

            let chatOK = self.reachabilityMonitor.isChatReachable
            let ttsOK = self.reachabilityMonitor.isTTSReachable

            if chatOK == true && ttsOK == true {
                self.autoResumeEnabled = true
                self.state = .listening
                self.startListening()
            } else {
                self.handleError(self.connectivityErrorMessage(chatOK: chatOK, ttsOK: ttsOK))
            }
        }
    }

    private func cancelConnectivityTask() {
        connectivityTask?.cancel()
        connectivityTask = nil
        connectivityAttemptID = nil
    }

    private func attemptReconnect() {
        activeChatViewModel?.cancelCurrentRequest()
        autoResumeEnabled = false
        cancelStartTasks()
        stopLoadingWatchdog()
        cancelConnectivityTask()
        isSendSuppressed = false
        speechInputManager.setHoldToSpeakActive(false)
        showErrorBanner = false
        errorMessage = nil

        let hasVoiceWork = audioManager.isRealtimeMode
            || audioManager.isLoading
            || audioManager.isAudioPlaying
            || !audioManager.dataTasks.isEmpty
        if hasVoiceWork {
            audioManager.closeAudioPlayer()
        }

        state = .loading
        beginConnectivityPreflight()
    }

    private func connectivityErrorMessage(chatOK: Bool?, ttsOK: Bool?) -> String {
        let chatBase = settingsManager.chatSettings.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let ttsBase = settingsManager.serverSettings.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        if chatBase.isEmpty || ttsBase.isEmpty {
            return NSLocalizedString("Server address is not configured.", comment: "Shown when realtime voice mode is started but server addresses are missing")
        }

        if chatOK == false && ttsOK == false {
            return NSLocalizedString("Unable to connect to the chat and voice servers.", comment: "Shown when both chat and voice servers are unreachable")
        }
        if chatOK == false {
            return NSLocalizedString("Unable to connect to the chat server.", comment: "Shown when the chat server is unreachable for realtime voice mode")
        }
        if ttsOK == false {
            return NSLocalizedString("Unable to connect to the voice server.", comment: "Shown when the voice server is unreachable for realtime voice mode")
        }
        return NSLocalizedString("Unable to connect. Please check your server settings.", comment: "Fallback message when realtime voice mode cannot connect")
    }

    private func startListening() {
        guard autoResumeEnabled else { return }
        guard isPresented else { return }
        guard !audioManager.isAudioPlaying else { return }
        guard !audioManager.isLoading else { return }
        if let activeChatViewModel, activeChatViewModel.isLoading || activeChatViewModel.isPriming {
            return
        }
        guard !speechInputManager.isRecording else { return }
        guard !isStartingRecording else { return }

        let attemptID = UUID()
        startAttemptID = attemptID
        isStartingRecording = true
        pendingRestartAfterStart = false

        startRecordingTask?.cancel()
        startRecordingTask = Task { [weak self] in
            guard let self else { return }
            await self.startRecordingSession()
            await MainActor.run {
                guard self.startAttemptID == attemptID else { return }
                self.isStartingRecording = false

                if self.pendingRestartAfterStart {
                    self.pendingRestartAfterStart = false
                    self.restartListening()
                }
            }
        }

        startWatchdogTask?.cancel()
        startWatchdogTask = Task { [weak self] in
            guard let self else { return }
            // Don't treat the permission prompt window as a hard startup failure.
            // We only start the watchdog timeout after the system permission flow resolves.
            while !Task.isCancelled {
                let snapshot = await MainActor.run { () -> (stillRelevant: Bool, isWaitingOnPermissions: Bool) in
                    guard self.startAttemptID == attemptID else { return (false, false) }
                    guard self.isPresented else { return (false, false) }
                    guard self.isStartingRecording else { return (false, false) }
                    guard !self.speechInputManager.isRecording else { return (false, false) }
                    return (true, self.speechInputManager.isRequestingPermissions)
                }

                guard snapshot.stillRelevant else { return }
                guard snapshot.isWaitingOnPermissions else { break }

                try? await Task.sleep(for: .milliseconds(200))
            }

            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                guard self.startAttemptID == attemptID else { return }
                guard self.isPresented else { return }
                guard self.isStartingRecording else { return }
                guard !self.speechInputManager.isRecording else { return }
                guard !self.speechInputManager.isRequestingPermissions else { return }
                self.isStartingRecording = false
                self.pendingRestartAfterStart = false
                self.startAttemptID = nil
                self.handleError(NSLocalizedString("Microphone is unavailable.", comment: "Shown when starting speech recognition takes too long"))
            }
        }
    }

    private func restartListening() {
        if isStartingRecording {
            pendingRestartAfterStart = true
            return
        }
        cleanupRecordingOnly()
        startListening()
    }

    private func startRecordingSession() async {
        await speechInputManager.startRecording(
            language: selectedLanguage,
            onPartial: { _ in },
            onFinal: { [weak self] text in
                guard let self else { return }
                self.handleRecognizedFinal(text)
            }
        )
        if let error = speechInputManager.lastError, !error.isEmpty {
            handleError(error)
        }
    }

    private func handleRecognizedFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isSendSuppressed {
            // User is holding the long press, so suppress automatic sending.
            return
        }

        sendRecognizedText(trimmed)
    }

    private func handleListeningTap() {
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

    private func sendRecognizedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showErrorBanner = false
        errorMessage = nil
        state = .loading
        startLoadingWatchdog()
        onRecognizedFinal?(trimmed)
    }

    private func cleanupRecordingOnly() {
        speechInputManager.setHoldToSpeakActive(false)
        speechInputManager.stopRecording(finalize: false)
    }

    private func cleanupSession() {
        onRecognizedFinal = nil
        cancelStartTasks()
        stopLoadingWatchdog()
        cancelConnectivityTask()
        cleanupRecordingOnly()
        sessionCancellables.removeAll()
    }

    private func cancelStartTasks() {
        startRecordingTask?.cancel()
        startRecordingTask = nil
        startWatchdogTask?.cancel()
        startWatchdogTask = nil
        startAttemptID = nil
        pendingRestartAfterStart = false
        isStartingRecording = false
    }

    private func startLoadingWatchdog() {
        stopLoadingWatchdog()
        lastLoadingProgressAt = Date()
        loadingWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard self.isPresented else { return }
                guard self.state == .loading else { return }

                let last = self.lastLoadingProgressAt ?? Date()
                let timeout = self.audioManager.dataTasks.isEmpty ? self.loadingStallTimeout : self.loadingStallTimeoutWithActiveAudioRequests
                if Date().timeIntervalSince(last) > timeout {
                    self.activeChatViewModel?.cancelCurrentRequest()
                    let hasVoiceWork = self.audioManager.isRealtimeMode
                        || self.audioManager.isLoading
                        || self.audioManager.isAudioPlaying
                        || !self.audioManager.dataTasks.isEmpty
                    if hasVoiceWork {
                        self.audioManager.closeAudioPlayer()
                    }
                    self.handleError(NSLocalizedString("Connection timed out", comment: "Shown when voice mode stalls without progress"))
                    return
                }
            }
        }
    }

    private func stopLoadingWatchdog() {
        loadingWatchdogTask?.cancel()
        loadingWatchdogTask = nil
        lastLoadingProgressAt = nil
    }

    private func markLoadingProgress() {
        guard state == .loading else { return }
        lastLoadingProgressAt = Date()
    }

    private func interruptActiveWorkOnDismiss() {
        activeChatViewModel?.cancelCurrentRequest()
        stopLoadingWatchdog()

        let hasVoiceWork = audioManager.isRealtimeMode
            || audioManager.isLoading
            || audioManager.isAudioPlaying
            || !audioManager.dataTasks.isEmpty

        if hasVoiceWork {
            audioManager.closeAudioPlayer()
        }
    }

    private func interruptActiveWorkAndRestartListening() {
        activeChatViewModel?.cancelCurrentRequest()
        autoResumeEnabled = true
        cancelStartTasks()
        stopLoadingWatchdog()
        cancelConnectivityTask()
        isSendSuppressed = false
        showErrorBanner = false
        errorMessage = nil

        if audioManager.isRealtimeMode
            || audioManager.isLoading
            || audioManager.isAudioPlaying
            || !audioManager.dataTasks.isEmpty {
            audioManager.closeAudioPlayer()
        }

        state = .listening
        restartListening()
    }

    private func handleRecordingChange(_ isRecording: Bool) {
        if case .error = state { return }
        if isRecording {
            stopLoadingWatchdog()
            state = .listening
        } else {
            resumeListeningIfIdle()
        }
    }

    private func handleAudioPlayingChange(_ playing: Bool) {
        if case .error = state { return }
        if playing {
            stopLoadingWatchdog()
            state = .speaking
        } else {
            resumeListeningIfIdle()
        }
    }

    private func handleAudioLoadingChange(_ loading: Bool) {
        if case .error = state { return }
        if loading, !audioManager.isAudioPlaying {
            state = .loading
            startLoadingWatchdog()
        } else {
            stopLoadingWatchdog()
            resumeListeningIfIdle()
        }
    }

    private func resumeListeningIfIdle() {
        guard autoResumeEnabled, isPresented else { return }
        // Avoid restarting the microphone while we're in the middle of sending/loading a response.
        guard loadingWatchdogTask == nil else { return }
        guard !audioManager.isAudioPlaying else { return }
        guard !audioManager.isLoading else { return }
        guard !speechInputManager.isRecording else { return }
        startListening()
    }

    private func handleError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if case let .error(existing) = state, existing == trimmed {
            return
        }
        errorMessage = trimmed
        showErrorBanner = true
        state = .error(trimmed)
        autoResumeEnabled = false
        cancelStartTasks()
        stopLoadingWatchdog()
        cancelConnectivityTask()
        speechInputManager.setHoldToSpeakActive(false)
        cleanupRecordingOnly()

        activeChatViewModel?.cancelCurrentRequest()
        let hasVoiceWork = audioManager.isRealtimeMode
            || audioManager.isLoading
            || audioManager.isAudioPlaying
            || !audioManager.dataTasks.isEmpty
        if hasVoiceWork {
            audioManager.closeAudioPlayer()
        }
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
