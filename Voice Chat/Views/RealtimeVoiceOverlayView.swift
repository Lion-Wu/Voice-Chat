//
//  RealtimeVoiceOverlayView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

struct RealtimeVoiceOverlayView: View {
    @ObservedObject var viewModel: VoiceChatOverlayViewModel
    @EnvironmentObject var errorCenter: AppErrorCenter
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
    @State private var circlePressTask: Task<Void, Never>?
    @State private var isCirclePressed: Bool = false
    @State private var didTriggerCircleLongPress: Bool = false
    @State private var interactionPulse: CGFloat = 1

    private let stateAnimation = Animation.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.2)
    private let defaultBaseSize: CGFloat = 200
    private let listeningBaseSize: CGFloat = 280
    private let circleLongPressThreshold: UInt64 = 450_000_000

    private var circleBaseColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var circleErrorRingColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.28)
    }

    private var overlayErrorText: String? {
        if case let .error(message) = viewModel.state {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
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
                            .foregroundStyle(circleBaseColor.opacity(0.92))
                            .shadow(radius: 6)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(spacing: 18) {
                ZStack {
                    let baseSize: CGFloat = (viewModel.state == .listening) ? listeningBaseSize : defaultBaseSize
                    Group {
                        if overlayErrorText != nil {
                            Circle()
                                .strokeBorder(circleErrorRingColor, lineWidth: 14)
                        } else {
                            Circle()
                                .fill(circleBaseColor)
                        }
                    }
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(displayedScale * interactionPulse * circlePressScale)
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 6)
                    .contentShape(Circle())
                    .gesture(circleGesture)
                }

                if let message = overlayErrorText {
                    Button {
                        triggerTapAction()
                    } label: {
                        VStack(spacing: 6) {
                            Text(message)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .minimumScaleFactor(0.85)

                            Text(NSLocalizedString("Tap to reconnect", comment: "Shown under the realtime voice overlay when an error occurs"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
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
        .overlay(alignment: .bottom) {
            if !errorCenter.notices.isEmpty {
                ErrorNoticeStack(
                    notices: errorCenter.notices,
                    onDismiss: { notice in
                        errorCenter.dismiss(notice)
                        viewModel.dismissErrorMessage()
                    }
                )
                // Keep it behind the language picker / controls.
                .padding(.bottom, 12)
                .zIndex(0)
            }
        }
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
        cancelCirclePressTask()
        viewModel.handleViewDisappear()
    }

    private func closeOverlay() {
        viewModel.dismiss()
        onClose()
    }

    private var circlePressScale: CGFloat {
        isCirclePressed ? 0.93 : 1.0
    }

    private var circleGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                beginCirclePressIfNeeded()
            }
            .onEnded { _ in
                endCirclePress()
            }
    }

    private func beginCirclePressIfNeeded() {
        guard !isCirclePressed else { return }
        isCirclePressed = true
        didTriggerCircleLongPress = false
        cancelCirclePressTask()
        circlePressTask = Task { [weak viewModel] in
            do {
                try await Task.sleep(nanoseconds: circleLongPressThreshold)
            } catch {
                return
            }
            await MainActor.run {
                guard isCirclePressed else { return }
                guard !didTriggerCircleLongPress else { return }
                didTriggerCircleLongPress = true
                triggerLongPressAction(viewModel: viewModel)
            }
        }
    }

    private func endCirclePress() {
        guard isCirclePressed else { return }
        isCirclePressed = false
        cancelCirclePressTask()

        if didTriggerCircleLongPress {
            viewModel.handleCircleLongPressEnded()
        } else {
            triggerTapAction()
        }
        didTriggerCircleLongPress = false
    }

    private func cancelCirclePressTask() {
        circlePressTask?.cancel()
        circlePressTask = nil
    }

    private func triggerTapAction() {
        animateInteractionPulse()
        viewModel.handleCircleTap()
    }

    private func triggerLongPressAction(viewModel: VoiceChatOverlayViewModel?) {
        animateInteractionPulse(strength: 1.10)
        viewModel?.handleCircleLongPressBegan()
    }

    private func animateInteractionPulse(strength: CGFloat = 1.06) {
        interactionPulse = strength
        withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
            interactionPulse = 1.0
        }
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
