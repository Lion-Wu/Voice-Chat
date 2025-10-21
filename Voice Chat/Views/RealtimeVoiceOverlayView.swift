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

    /// Called when the overlay should close
    var onClose: () -> Void = {}

    /// Sends the recognized text back to the host view
    var onTextFinal: (String) -> Void = { _ in }

    // Phase accumulator for the loading pulse animation
    @State private var pulsePhase: Double = 0
    @State private var showErrorToast: Bool = false

    private enum OverlayState: Equatable {
        case listening
        case loading
        case speaking
        case error(String)
    }
    @State private var state: OverlayState = .listening

    // Shared animation used when transitioning between states
    private let stateAnim = Animation.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.2)

    // Adjust the base circle color for the current appearance
    private var circleBaseColor: Color { colorScheme == .dark ? .white : .black }

    // Internal state used to smooth level and scale transitions
    @State private var smoothedInputLevel: CGFloat = 0.0   // Input volume for listening state
    @State private var smoothedOutputLevel: CGFloat = 0.0  // Output volume for speaking state
    @State private var targetScale: CGFloat = 1.0
    @State private var displayedScale: CGFloat = 1.0
    @State private var pulseTimer: Timer?

    // Base circle sizes for listening and idle states
    private let defaultBaseSize: CGFloat = 200
    private let listeningBaseSize: CGFloat = 280

    // MARK: - Body
    var body: some View {
        ZStack {
            // Use an opaque background to avoid showing underlying content
            PlatformColor.systemBackground
                .ignoresSafeArea()

            VStack(spacing: 28) {

                // Close button (top right)
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

            // Animated listening/speaking circle
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
                    .scaleEffect(displayedScale)
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 6)
            }
            .animation(stateAnim, value: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            // Initialize the scale to avoid an initial jump
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
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
        // React to recording and playback changes, returning to listening when idle
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
                title: Text(L10n.VoiceOverlay.errorTitle),
                message: Text(speechInputManager.lastError ?? L10n.VoiceOverlay.errorUnknown),
                dismissButton: .default(Text(L10n.General.ok))
            )
        }
    }

    // MARK: - Helpers

    private func startListening() {
        // Avoid starting multiple recording sessions
        if speechInputManager.isRecording { return }
        withAnimation(stateAnim) { state = .listening }
        Task { @MainActor in
            await speechInputManager.startRecording(
                language: speechInputManager.currentLanguage,
                onPartial: { _ in },
                onFinal: { text in
                    // Forward the final text and allow the host to control loading/speaking transitions
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
        // Automatically resume listening when neither recording nor playback is active
        if !speechInputManager.isRecording,
           !audioManager.isAudioPlaying,
           !audioManager.isLoading {
            startListening()
        }
    }

    private func stopIfNeeded() {
        if speechInputManager.isRecording { speechInputManager.stopRecording() }
    }

    // Determine the target scale for the animated circle based on state
    private func circleTargetScale() -> CGFloat {
        switch state {
        case .listening:
            // Listening: scale based on the smoothed input level
            return 1.0 + 0.32 * smoothedInputLevel
        case .speaking:
            // Speaking: scale based on the smoothed output level
            return 1.0 + 0.32 * smoothedOutputLevel
        case .loading:
            // Loading: reuse the legacy speaking pulse animation
            return 0.95 + 0.10 * CGFloat((sin(pulsePhase) + 1) * 0.5)
        case .error:
            return 1.0
        }
    }

    private func startPulse() {
        stopPulse()
        // Drive the animation phase and smooth the scale using a timer
        let timer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { _ in
            Task { @MainActor in
                // Advance the phase; reuse the legacy cadence while loading and keep the standard pace otherwise
                let step: Double = (state == .loading) ? 0.06 : 0.12
                pulsePhase += step
                if pulsePhase > .pi * 2 { pulsePhase -= .pi * 2 }

                // Low-pass filter the input level (listening)
                let inRaw = CGFloat(min(1.0, max(0.0, speechInputManager.inputLevel)))
                let inAlpha: CGFloat = 0.20
                smoothedInputLevel += (inRaw - smoothedInputLevel) * inAlpha

                // Low-pass filter the output level (playback)
                let outRaw = CGFloat(min(1.0, max(0.0, audioManager.outputLevel)))
                let outAlpha: CGFloat = 0.20
                smoothedOutputLevel += (outRaw - smoothedOutputLevel) * outAlpha

                // Update the target scale and ease the displayed value toward it
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
        // Immediately sync the displayed scale to avoid jumps when the state changes
        targetScale = circleTargetScale()
        displayedScale = targetScale
    }
}
