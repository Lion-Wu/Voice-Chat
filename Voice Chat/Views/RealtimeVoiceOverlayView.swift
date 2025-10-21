//
//  RealtimeVoiceOverlayView.swift
//  Voice Chat
//

import SwiftUI

struct RealtimeVoiceOverlayView: View {
    @EnvironmentObject var speechInputManager: SpeechInputManager
    @EnvironmentObject var audioManager: GlobalAudioManager
    @Environment(\.colorScheme) private var colorScheme

    /// Invoked when the user dismisses the overlay so the host can close any presentation.
    var onClose: () -> Void = {}

    /// Invoked when dictation produces a final transcript that should be sent to the chat session.
    var onTextFinal: (String) -> Void = { _ in }

    @State private var pulsePhase: Double = 0
    @State private var showErrorToast: Bool = false

    private enum OverlayState: Equatable {
        case listening
        case loading
        case speaking
        case error(String)
    }

    @State private var state: OverlayState = .listening

    private let stateAnimation = Animation.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.2)

    private var circleBaseColor: Color { colorScheme == .dark ? .white : .black }

    // Smoothed levels keep the visualisation stable across recording and playback.
    @State private var smoothedInputLevel: CGFloat = 0.0
    @State private var smoothedOutputLevel: CGFloat = 0.0
    @State private var targetScale: CGFloat = 1.0
    @State private var displayedScale: CGFloat = 1.0
    @State private var pulseTimer: Timer?

    private let defaultBaseSize: CGFloat = 200
    private let listeningBaseSize: CGFloat = 280

    var body: some View {
        ZStack {
            PlatformColor.systemBackground
                .ignoresSafeArea()

            VStack(spacing: 28) {
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

            ZStack {
                let baseSize: CGFloat = (state == .listening) ? listeningBaseSize : defaultBaseSize
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                circleBaseColor.opacity(0.95),
                                circleBaseColor.opacity(0.78)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: baseSize * 0.8
                        )
                    )
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(displayedScale)
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 6)
            }
            .animation(stateAnimation, value: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
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
                    ForEach(SpeechInputManager.DictationLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: speechInputManager.isRecording) { _, recording in
            if recording {
                withAnimation(stateAnimation) { state = .listening }
            }
        }
        .onChange(of: audioManager.isAudioPlaying) { _, playing in
            if playing {
                withAnimation(stateAnimation) { state = .speaking }
            } else {
                autoResumeListeningIfIdle()
            }
        }
        .onChange(of: audioManager.isLoading) { _, loading in
            if loading && !audioManager.isAudioPlaying {
                withAnimation(stateAnimation) { state = .loading }
            } else {
                autoResumeListeningIfIdle()
            }
        }
        .alert(isPresented: $showErrorToast) {
            Alert(
                title: Text("Voice Error"),
                message: Text(speechInputManager.lastError ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Dictation lifecycle

    private func startListening() {
        guard !speechInputManager.isRecording else { return }
        withAnimation(stateAnimation) { state = .listening }
        Task { @MainActor in
            await speechInputManager.startRecording(
                language: speechInputManager.currentLanguage,
                onPartial: { _ in },
                onFinal: { text in
                    onTextFinal(text)
                    withAnimation(stateAnimation) { state = .loading }
                }
            )
            if let error = speechInputManager.lastError, !error.isEmpty {
                withAnimation(stateAnimation) { state = .error(error) }
                showErrorToast = true
            }
        }
    }

    private func autoResumeListeningIfIdle() {
        if !speechInputManager.isRecording,
           !audioManager.isAudioPlaying,
           !audioManager.isLoading {
            startListening()
        }
    }

    private func stopIfNeeded() {
        if speechInputManager.isRecording { speechInputManager.stopRecording() }
    }

    // MARK: - Visuals

    private func circleTargetScale() -> CGFloat {
        switch state {
        case .listening:
            return 1.0 + 0.32 * smoothedInputLevel
        case .speaking:
            return 1.0 + 0.24 * smoothedOutputLevel
        case .loading:
            return 1.05 + 0.04 * CGFloat(sin(pulsePhase))
        case .error:
            return 1.0
        }
    }

    private func syncStateWithEngines() {
        if audioManager.isAudioPlaying {
            state = .speaking
        } else if audioManager.isLoading {
            state = .loading
        } else {
            state = .listening
        }
    }

    private func startPulse() {
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            pulsePhase += 0.075
            smoothedInputLevel = lerp(from: smoothedInputLevel, to: speechInputManager.inputLevel, alpha: 0.25)
            smoothedOutputLevel = lerp(from: smoothedOutputLevel, to: audioManager.outputLevel, alpha: 0.18)
            targetScale = circleTargetScale()
            displayedScale = lerp(from: displayedScale, to: targetScale, alpha: 0.18)
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    private func lerp(from current: CGFloat, to target: CGFloat, alpha: CGFloat) -> CGFloat {
        current + (target - current) * alpha
    }
}
