//
//  RealtimeVoiceOverlayView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

struct RealtimeVoiceOverlayView: View {
    @EnvironmentObject var speechInputManager: SpeechInputManager
    @EnvironmentObject var audioManager: GlobalAudioManager
    @Environment(\.colorScheme) private var colorScheme

    /// Called when the host needs to dismiss the overlay.
    var onClose: () -> Void = {}

    /// Called when speech recognition finishes so the host can send the text to the chat.
    var onTextFinal: (String) -> Void = { _ in }

    // Phase used for the pulsing placeholder animation while loading or speaking.
    @State private var pulsePhase: Double = 0
    @State private var showErrorToast: Bool = false

    private enum OverlayState: Equatable {
        case listening
        case loading
        case speaking
        case error(String)
    }
    @State private var state: OverlayState = .listening

    // Shared animation used for state transitions.
    private let stateAnim = Animation.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.2)

    // Change the base circle color depending on the active color scheme.
    private var circleBaseColor: Color { colorScheme == .dark ? .white : .black }

    // Internal state used to smooth transitions and scale updates.
    @State private var smoothedInputLevel: CGFloat = 0.0   // Smoothed recording level used in the listening state.
    @State private var smoothedOutputLevel: CGFloat = 0.0  // Smoothed playback level used in the speaking state.
    @State private var targetScale: CGFloat = 1.0
    @State private var displayedScale: CGFloat = 1.0
    @State private var pulseTimer: Timer?

    // Base circle sizes for idle and listening states.
    private let defaultBaseSize: CGFloat = 200
    private let listeningBaseSize: CGFloat = 280

    // MARK: - Body
    var body: some View {
        ZStack {
            // Use an opaque background to prevent the underlying view from bleeding through.
            PlatformColor.systemBackground
                .ignoresSafeArea()

            VStack(spacing: 28) {

                // Close button (top-right)
                HStack {
                    Spacer()
                    Button {
                        stopIfNeeded()
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.95))
                            .shadow(radius: 6)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Main circular visualization
            ZStack {
                let baseSize: CGFloat = (state == .listening) ? listeningBaseSize : defaultBaseSize
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                circleBaseColor.opacity(0.95),
                            circleBaseColor.opacity(0.78)
                            ],
                            center: .center, startRadius: 2, endRadius: baseSize * 0.8
                        )
                    )
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(displayedScale) // Apply the smoothed scale value.
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 6)
            }
            .animation(stateAnim, value: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            // Initialize the scale to avoid a jump on first appearance.
            targetScale = circleTargetScale()
            displayedScale = targetScale
            startListening()
            startPulse()
            syncStateWithEngines()
        }
        .onDisappear {
            stopPulse()
            speechInputManager.stopRecording()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
                Picker("", selection: Binding(
                    get: { speechInputManager.currentLanguage },
                    set: { speechInputManager.currentLanguage = $0 }
                )) {
                    ForEach(SpeechInputManager.DictationLanguage.allCases) { lang in
                        Text(lang.displayNameKey).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
        // Update the overlay state in response to recording and playback changes.
        .onChange(of: speechInputManager.isRecording) { _, recording in
            if recording {
                withAnimation(stateAnim) { state = .listening }
            }
        }
        .onChange(of: audioManager.isAudioPlaying) { _, playing in
            if playing {
                withAnimation(stateAnim) { state = .speaking }
            } else {
                autoResumeListeningIfIdle()
            }
        }
        .onChange(of: audioManager.isLoading) { _, loading in
            if loading && !audioManager.isAudioPlaying {
                withAnimation(stateAnim) { state = .loading }
            } else {
                autoResumeListeningIfIdle()
            }
        }
        .alert(isPresented: $showErrorToast) {
            Alert(
                title: Text(L10n.Overlay.voiceErrorTitle),
                message: Text(speechInputManager.lastError ?? L10n.Overlay.voiceErrorFallback),
                dismissButton: .default(Text(L10n.Common.ok))
            )
        }
    }

    // MARK: - Helpers

    private func startListening() {
        // Avoid restarting if recording is already active.
        if speechInputManager.isRecording { return }
        withAnimation(stateAnim) { state = .listening }
        Task { @MainActor in
            await speechInputManager.startRecording(
                language: speechInputManager.currentLanguage,
                onPartial: { _ in },
                onFinal: { text in
                    // Forward the final text to the host and transition into the loading state.
                    onTextFinal(text)
                    withAnimation(stateAnim) { state = .loading }
                }
            )
            if let err = speechInputManager.lastError, !err.isEmpty {
                withAnimation(stateAnim) { state = .error(err) }
                showErrorToast = true
            }
        }
    }

    private func autoResumeListeningIfIdle() {
        // When idle, resume listening and restart recognition automatically.
        if !speechInputManager.isRecording,
           !audioManager.isAudioPlaying,
           !audioManager.isLoading {
            startListening()
        }
    }

    private func stopIfNeeded() {
        if speechInputManager.isRecording { speechInputManager.stopRecording() }
    }

    // Determine the target scale for each visual state.
    private func circleTargetScale() -> CGFloat {
        switch state {
        case .listening:
            // Scale the circle based on the current input level.
            return 1.0 + 0.32 * smoothedInputLevel
        case .speaking:
            // Scale based on the current output level while speaking.
            return 1.0 + 0.32 * smoothedOutputLevel
        case .loading:
            // Use a subtle pulse while waiting for audio segments.
            return 0.95 + 0.10 * CGFloat((sin(pulsePhase) + 1) * 0.5)
        case .error:
            return 1.0
        }
    }

    private func startPulse() {
        stopPulse()
        // Advance the animation phase and smooth the levels with a timer.
        let timer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { _ in
            Task { @MainActor in
                // Advance the phase. Use a slower pace while loading.
                let step: Double = (state == .loading) ? 0.06 : 0.12
                pulsePhase += step
                if pulsePhase > .pi * 2 { pulsePhase -= .pi * 2 }

                // Low-pass filter for the input level (listening state)
                let inRaw = CGFloat(min(1.0, max(0.0, speechInputManager.inputLevel)))
                let inAlpha: CGFloat = 0.20
                smoothedInputLevel += (inRaw - smoothedInputLevel) * inAlpha

                // Low-pass filter for the output level (speaking state)
                let outRaw = CGFloat(min(1.0, max(0.0, audioManager.outputLevel)))
                let outAlpha: CGFloat = 0.20
                smoothedOutputLevel += (outRaw - smoothedOutputLevel) * outAlpha

                // Compute the target scale and apply smoothing.
                targetScale = circleTargetScale()
                let k: CGFloat = 0.20
                displayedScale += (targetScale - displayedScale) * k
            }
        }
        timer.tolerance = 0.005
        pulseTimer = timer
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulsePhase = 0
    }

    private func syncStateWithEngines() {
        if audioManager.isAudioPlaying {
            withAnimation(stateAnim) { state = .speaking }
        } else if audioManager.isLoading {
            withAnimation(stateAnim) { state = .loading }
        } else if speechInputManager.isRecording {
            withAnimation(stateAnim) { state = .listening }
        } else {
            withAnimation(stateAnim) { state = .listening }
        }
        // Synchronize the displayed scale to avoid abrupt jumps when states change.
        targetScale = circleTargetScale()
        displayedScale = targetScale
    }
}
