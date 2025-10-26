//
//  RealtimeVoiceOverlayView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

struct RealtimeVoiceOverlayView: View {
    @ObservedObject var viewModel: VoiceChatOverlayViewModel
    @Environment(\.colorScheme) private var colorScheme

    /// Optional callback so the parent can react when the overlay is dismissed.
    var onClose: () -> Void = {}

    // Animation state
    @State private var pulsePhase: Double = 0
    @State private var smoothedInputLevel: CGFloat = 0
    @State private var smoothedOutputLevel: CGFloat = 0
    @State private var targetScale: CGFloat = 1
    @State private var displayedScale: CGFloat = 1
    @State private var pulseTimer: Timer?

    private let stateAnimation = Animation.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.2)
    private let defaultBaseSize: CGFloat = 200
    private let listeningBaseSize: CGFloat = 280

    private var circleBaseColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        ZStack {
            PlatformColor.systemBackground
                .ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    Button {
                        closeOverlay()
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
                let baseSize: CGFloat = (viewModel.state == .listening) ? listeningBaseSize : defaultBaseSize
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
            .animation(stateAnimation, value: viewModel.state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            configureInitialState()
            startPulse()
        }
        .onDisappear {
            teardown()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
                Picker("", selection: Binding(
                    get: { viewModel.selectedLanguage },
                    set: { viewModel.updateLanguage($0) }
                )) {
                    ForEach(viewModel.availableLanguages) { language in
                        Text(language.defaultDisplayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .alert(
            Text("Speech Error"),
            isPresented: Binding(
                get: { viewModel.showErrorAlert },
                set: { newValue in
                    if !newValue {
                        viewModel.dismissErrorMessage()
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    viewModel.dismissErrorMessage()
                }
            },
            message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        )
        .onChange(of: viewModel.state) { _, newState in
            targetScale = circleTargetScale(for: newState)
        }
    }

    // MARK: - Lifecycle helpers

    private func configureInitialState() {
        targetScale = circleTargetScale(for: viewModel.state)
        displayedScale = targetScale
    }

    private func teardown() {
        stopPulse()
        viewModel.handleViewDisappear()
    }

    private func closeOverlay() {
        viewModel.dismiss()
        onClose()
    }

    // MARK: - Animation helpers

    private func circleTargetScale(for state: VoiceChatOverlayViewModel.OverlayState) -> CGFloat {
        switch state {
        case .listening:
            return 1.0 + 0.32 * smoothedInputLevel
        case .speaking:
            return 1.0 + 0.32 * smoothedOutputLevel
        case .loading:
            return 0.95 + 0.10 * CGFloat((sin(pulsePhase) + 1) * 0.5)
        case .error:
            return 1.0
        }
    }

    private func startPulse() {
        stopPulse()
        let timer = Timer.scheduledTimer(withTimeInterval: 1 / 60.0, repeats: true) { _ in
            Task { @MainActor in
                let phaseStep: Double = (viewModel.state == .loading) ? 0.06 : 0.12
                pulsePhase += phaseStep
                if pulsePhase > .pi * 2 {
                    pulsePhase -= .pi * 2
                }

                let input = CGFloat(min(1.0, max(0.0, viewModel.inputLevel)))
                let output = CGFloat(min(1.0, max(0.0, viewModel.outputLevel)))

                smoothedInputLevel += (input - smoothedInputLevel) * 0.20
                smoothedOutputLevel += (output - smoothedOutputLevel) * 0.20

                targetScale = circleTargetScale(for: viewModel.state)
                displayedScale += (targetScale - displayedScale) * 0.20
            }
        }
        timer.tolerance = 0.005
        pulseTimer = timer
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulsePhase = 0
        smoothedInputLevel = 0
        smoothedOutputLevel = 0
        targetScale = 1
        displayedScale = 1
    }
}
