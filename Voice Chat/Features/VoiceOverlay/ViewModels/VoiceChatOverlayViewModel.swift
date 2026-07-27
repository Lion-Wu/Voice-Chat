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
        case connecting
        case listening
        case loading
        case speaking
        case error(String)
    }

    @Published var isPresented: Bool = false
    @Published var state: OverlayState = .listening
    @Published var selectedLanguage: SpeechInputManager.DictationLanguage
    @Published var showErrorBanner: Bool = false
    @Published var errorMessage: String?
    @Published var isVisionCapturePresented: Bool = false
    @Published var isVisionCaptureRecording: Bool = false
    @Published var isVisionCaptureSamplingActive: Bool = false
    @Published var visionCaptureSampleCount: Int = 0
    @Published var visionCaptureResetID = UUID()
    @Published var realtimeAssistantSnapshot: RealtimeVoiceAssistantSnapshot?
    var isSendSuppressed: Bool = false

    var availableLanguages: [SpeechInputManager.DictationLanguage] {
        SpeechInputManager.DictationLanguage.allCases
    }

    var isVisionCaptureAvailable: Bool {
        activeChatSession?.supportsRealtimeVoiceImageInput == true
    }

    let speechInputManager: SpeechInputManager
    let audioManager: GlobalAudioManager
    let errorCenter: AppErrorCenter
    let settingsManager: SettingsManager
    let reachabilityMonitor: ServerReachabilityMonitor
    var cancellables: Set<AnyCancellable> = []
    var sessionCancellables: Set<AnyCancellable> = []
    var onRecognizedFinal: ((String, [ChatImageAttachment]) -> Void)?
    weak var activeChatSession: (any RealtimeVoiceChatSession)?
    var visionCaptureCoordinator = VoiceVisionCaptureCoordinator()
    var hasDetectedSpeechForCurrentVisionCapture = false
    var autoResumeEnabled = false
    var recordingStartCoordinator = VoiceRecordingStartCoordinator()
    var isStartingRecording: Bool { recordingStartCoordinator.isStartingRecording }
    let loadingWatchdog = VoiceLoadingWatchdog()
    var connectivityTask: Task<Void, Never>?
    var connectivityAttemptID: UUID?
    let overlayAnimation = Animation.spring(response: 0.4, dampingFraction: 0.85)

    var inputMotionAudioSource: VoiceMicrophoneAudioSource {
        speechInputManager.inputMotionAudioSource
    }

    var outputMotionAudioSource: VoiceAudioLevelStore {
        audioManager.outputMotionAudioSource
    }

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

    func presentSession(chatSession: (any RealtimeVoiceChatSession)? = nil, onFinal: @escaping (String, [ChatImageAttachment]) -> Void) {
        activeChatSession = chatSession
        bindSession(chatSession: chatSession)
        onRecognizedFinal = onFinal
        autoResumeEnabled = false
        isSendSuppressed = false
        resetVisionCaptureSamples()
        resetVisionCaptureSpeechActivity()
        inputMotionAudioSource.reset()
        outputMotionAudioSource.store(.silent)
        showErrorBanner = false
        errorMessage = nil
        realtimeAssistantSnapshot = nil
        withAnimation(overlayAnimation) {
            isPresented = true
        }
        state = .connecting
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
        realtimeAssistantSnapshot = nil
        dismissVisionCapture()
        resetVisionCaptureSpeechActivity()
        inputMotionAudioSource.reset()
        outputMotionAudioSource.store(.silent)
        cleanupSession()
        activeChatSession = nil
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
        case .connecting:
            // Don't let a tap bypass the initial connectivity preflight.
            return
        case .listening:
            handleListeningTap()
        case .error:
            attemptReconnect()
        case .loading:
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

    func performHoldToTalkAccessibilityAction() {
        if speechInputManager.isHoldToSpeakActive || isStartingRecording {
            handleCircleLongPressEnded()
        } else {
            handleCircleLongPressBegan()
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

    func refreshRealtimeAssistantSnapshot() {
        realtimeAssistantSnapshot = activeChatSession?.realtimeVoiceAssistantSnapshot
    }

    func resolveRealtimeVoiceToolAuthorization(requestID: String, allowed: Bool) {
        activeChatSession?.resolveRealtimeVoiceToolAuthorization(requestID: requestID, allowed: allowed)
        refreshRealtimeAssistantSnapshot()
    }

}
