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

    /// Closure invoked when the overlay requests dismissal.
    var onClose: () -> Void = {}

    /// Closure that delivers the final recognized text back to the host chat view.
    var onTextFinal: (String) -> Void = { _ in }

    // Phase accumulator used to drive the pulsing animation while loading or playing back audio.
    @State private var pulsePhase: Double = 0
    @State private var showErrorToast: Bool = false

    private enum OverlayState: Equatable {
        case listening
        case loading
        case speaking
        case error(String)
    }
    @State private var state: OverlayState = .listening

    // Unified animation for all state transitions.
    private let stateAnim = Animation.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.2)

    // Base circle color adapts to the system appearance (light/dark).
    private var circleBaseColor: Color { colorScheme == .dark ? .white : .black }

    // Internal state for smoothing level-driven scale transitions.
    @State private var smoothedInputLevel: CGFloat = 0.0   // Microphone input level when listening
    @State private var smoothedOutputLevel: CGFloat = 0.0  // Playback output level when speaking
    @State private var targetScale: CGFloat = 1.0
    @State private var displayedScale: CGFloat = 1.0
    @State private var pulseTimer: Timer?

    // Base circle sizes (listening mode is intentionally larger for visual distinction)
    private let defaultBaseSize: CGFloat = 200
    private let listeningBaseSize: CGFloat = 280

    // MARK: - Body
    var body: some View {
        ZStack {
            // Use an opaque background to avoid showing content underneath the overlay.
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

            // Central animated circle
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
                    .scaleEffect(displayedScale) // Apply the smoothed scale value
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 6)
            }
            .animation(stateAnim, value: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            // Initialize the scale to avoid a pop on first appearance.
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
        // Dynamically update the overlay state based on recording/playback activity.
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
                title: Text("Voice error"),
                message: Text(speechInputManager.lastError ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Helpers

    private func startListening() {
        // Avoid reinitializing the session if we are already recording.
        if speechInputManager.isRecording { return }
        withAnimation(stateAnim) { state = .listening }
        Task { @MainActor in
            await speechInputManager.startRecording(
                language: speechInputManager.currentLanguage,
                onPartial: { _ in },
                onFinal: { text in
                    // Deliver the text back to the host and let the chat view manage playback state.
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
        // Resume listening whenever no recording or playback is active.
        if !speechInputManager.isRecording,
           !audioManager.isAudioPlaying,
           !audioManager.isLoading {
            startListening()
        }
    }

    private func stopIfNeeded() {
        if speechInputManager.isRecording { speechInputManager.stopRecording() }
    }

    // Determine the target scale for each overlay state.
    private func circleTargetScale() -> CGFloat {
        switch state {
        case .listening:
            // Listening mode reacts to microphone input levels.
            return 1.0 + 0.32 * smoothedInputLevel
        case .speaking:
            // Speaking mode scales according to playback intensity.
            return 1.0 + 0.32 * smoothedOutputLevel
        case .loading:
            // Loading mode uses a subtle pulsing animation.
            return 0.95 + 0.10 * CGFloat((sin(pulsePhase) + 1) * 0.5)
        case .error:
            return 1.0
        }
    }

    private func startPulse() {
        stopPulse()
        // Drive the pulse animation via a timer and smooth the resulting scale.
        let timer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { _ in
            Task { @MainActor in
                // Advance the animation phase with state-aware speed.
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

                // Compute the target scale and apply exponential smoothing.
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
        // Synchronize the scale once to prevent a visual jump when the state changes.
        targetScale = circleTargetScale()
        displayedScale = targetScale
    }
}
