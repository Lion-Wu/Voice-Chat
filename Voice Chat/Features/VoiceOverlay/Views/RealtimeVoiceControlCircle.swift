//
//  RealtimeVoiceControlCircle.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct VoiceMotionControlPlacement {
    let bounds: Anchor<CGRect>
    let visualScale: CGFloat
}

struct VoiceMotionControlPlacementPreferenceKey: PreferenceKey {
    static let defaultValue: VoiceMotionControlPlacement? = nil

    static func reduce(
        value: inout VoiceMotionControlPlacement?,
        nextValue: () -> VoiceMotionControlPlacement?
    ) {
        value = nextValue() ?? value
    }
}

struct RealtimeVoiceControlCircle: View {
    nonisolated static let standardFrameSize: CGFloat = 280

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewModel: VoiceChatOverlayViewModel
    let motionController: VoiceMotionController
    var displayStyle: RealtimeVoiceOverlayView.DisplayStyle = .standard
    var externalPulseToken: UUID?

    @State private var isCirclePressed = false
    @State private var isCircleHoldActive = false
    @State private var didTriggerCircleLongPress = false
    @State private var shouldSuppressCircleTapOnEnd = false
    @State private var circleGestureCancelled = false
    @State private var circlePressOrigin: CGPoint?
    @State private var pressedCircleBaseSize: CGFloat?
    @State private var longPressTriggerTask: Task<Void, Never>?
    @State private var interactionPulse: CGFloat = 1

    private let circlePressInAnimation = Animation.easeOut(duration: 0.12)
    private let circlePressOutAnimation = Animation.easeOut(duration: 0.15)
    private let circleLongPressDuration = 0.38
    private let circleLongPressMaximumDistance: CGFloat = 42

    private var overlayErrorText: String? {
        if case let .error(message) = viewModel.state {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private var accessibilityValue: String {
        switch viewModel.state {
        case .connecting:
            String(localized: "Connecting")
        case .listening:
            String(localized: "Listening")
        case .speaking:
            String(localized: "Speaking")
        case .loading:
            String(localized: "Thinking")
        case .error:
            String(localized: "Error")
        }
    }

    private var accessibilityHint: String {
        if overlayErrorText != nil {
            return String(localized: "Double-tap to reconnect.")
        }
        if viewModel.state == .connecting {
            return String(localized: "Wait for the voice session to finish connecting.")
        }
        if viewModel.state == .loading {
            return String(localized: "Wait for the model to finish generating a response.")
        }
        return String(localized: "Double-tap to control realtime voice. Use the Hold to talk action for push-to-talk.")
    }

    private var defaultBaseSize: CGFloat {
        #if os(iOS) || os(macOS)
        if viewModel.isVisionCapturePresented {
            return 86
        }
        #endif
        return isVisionSceneStyle ? 264 : 224
    }

    private var listeningBaseSize: CGFloat {
        #if os(iOS) || os(macOS)
        if viewModel.isVisionCapturePresented {
            return 108
        }
        #endif
        return isVisionSceneStyle ? 328 : Self.standardFrameSize
    }

    private var isVisionSceneStyle: Bool {
        #if os(visionOS)
        displayStyle == .visionScene
        #else
        false
        #endif
    }

    private var circleControlFrameSize: CGFloat {
        listeningBaseSize
    }

    private var currentInteractionDiameter: CGFloat {
        pressedCircleBaseSize ?? interactionDiameter(for: viewModel.state)
    }

    private var circlePressScale: CGFloat {
        if isCircleHoldActive { return 1.10 }
        return isCirclePressed ? 1.015 : 1
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: currentInteractionDiameter, height: currentInteractionDiameter)
                .contentShape(Circle())
                .highPriorityGesture(circlePressGesture)
                .scaleEffect(interactionPulse * circlePressScale)
        }
        .frame(width: circleControlFrameSize, height: circleControlFrameSize)
        .anchorPreference(
            key: VoiceMotionControlPlacementPreferenceKey.self,
            value: .bounds
        ) {
            VoiceMotionControlPlacement(
                bounds: $0,
                visualScale: interactionPulse * circlePressScale
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Realtime voice control")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            triggerTapAction()
        }
        .accessibilityAction(named: Text("Hold to talk")) {
            viewModel.performHoldToTalkAccessibilityAction()
        }
        .onAppear {
            configureMotion()
        }
        .onDisappear {
            teardown()
        }
        .onChange(of: viewModel.state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
        .onChange(of: externalPulseToken) { _, _ in
            animateInteractionPulse()
        }
        .onChange(of: accessibilityReduceMotion) { _, isEnabled in
            motionController.isReducedMotionEnabled = isEnabled
        }
        .onChange(of: colorScheme) { _, _ in
            updateMotionAccent()
        }
        #if os(iOS) || os(macOS)
        .onChange(of: viewModel.isVisionCapturePresented) { _, _ in
            endCirclePressVisualState()
        }
        #endif
    }

    private var circlePressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                handleCircleDragChanged(value)
            }
            .onEnded { _ in
                handleCircleDragEnded()
            }
    }

    private func configureMotion() {
        motionController.isReducedMotionEnabled = accessibilityReduceMotion
        updateMotionAccent()
        motionController.setAudioLevels(.silent)
        motionController.setState(motionState(for: viewModel.state), immediate: true)
        updateMotionAudioSource(for: viewModel.state)
    }

    private func teardown() {
        cancelPendingLongPressTrigger()
        resetInteractionState()
        motionController.setAudioSource(nil)
        motionController.setAudioLevels(.silent)
    }

    private func updateMotionAccent() {
        let channel: Float = colorScheme == .dark ? 1 : 0
        motionController.setAccentSRGB(red: channel, green: channel, blue: channel)
    }

    private func motionState(
        for state: VoiceChatOverlayViewModel.OverlayState
    ) -> VoiceMotionState {
        switch state {
        case .connecting:
            .connecting
        case .listening:
            .listening
        case .loading:
            .thinking
        case .speaking:
            .speaking
        case .error:
            .error
        }
    }

    private func interactionDiameter(
        for state: VoiceChatOverlayViewModel.OverlayState
    ) -> CGFloat {
        switch state {
        case .listening:
            listeningBaseSize
        case .connecting, .speaking, .loading, .error:
            defaultBaseSize
        }
    }

    private func handleCircleDragChanged(_ value: DragGesture.Value) {
        if circlePressOrigin == nil {
            beginCirclePress(at: value.startLocation)
        }
        guard let origin = circlePressOrigin else { return }

        let distance = hypot(value.location.x - origin.x, value.location.y - origin.y)
        guard distance > circleLongPressMaximumDistance else { return }
        guard !circleGestureCancelled else { return }

        circleGestureCancelled = true
        shouldSuppressCircleTapOnEnd = true
        cancelPendingLongPressTrigger()

        if didTriggerCircleLongPress {
            viewModel.handleCircleLongPressEnded()
            didTriggerCircleLongPress = false
        }

        endCirclePressVisualState()
    }

    private func handleCircleDragEnded() {
        cancelPendingLongPressTrigger()

        let didTriggerLongPress = didTriggerCircleLongPress
        let shouldSendTap = !circleGestureCancelled && !shouldSuppressCircleTapOnEnd

        if didTriggerLongPress {
            viewModel.handleCircleLongPressEnded()
        } else if shouldSendTap {
            triggerTapAction()
        }

        endCirclePressVisualState()

        didTriggerCircleLongPress = false
        isCircleHoldActive = false
        shouldSuppressCircleTapOnEnd = false
        circleGestureCancelled = false
        circlePressOrigin = nil
    }

    private func beginCirclePress(at start: CGPoint) {
        circlePressOrigin = start
        pressedCircleBaseSize = currentInteractionDiameter
        circleGestureCancelled = false
        didTriggerCircleLongPress = false
        isCircleHoldActive = false
        shouldSuppressCircleTapOnEnd = false
        withAnimation(circlePressInAnimation) {
            isCirclePressed = true
        }
        schedulePendingLongPressTrigger()
    }

    private func endCirclePressVisualState() {
        guard isCirclePressed || pressedCircleBaseSize != nil else { return }
        withAnimation(circlePressOutAnimation) {
            isCirclePressed = false
            isCircleHoldActive = false
            pressedCircleBaseSize = nil
        }
    }

    private func schedulePendingLongPressTrigger() {
        cancelPendingLongPressTrigger()
        longPressTriggerTask = Task { @MainActor in
            let delay = UInt64(circleLongPressDuration * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard isCirclePressed else { return }
            guard !circleGestureCancelled else { return }
            guard !didTriggerCircleLongPress else { return }
            shouldSuppressCircleTapOnEnd = true
            didTriggerCircleLongPress = triggerLongPressAction(viewModel: viewModel)
            if didTriggerCircleLongPress {
                withAnimation(circlePressInAnimation) {
                    isCircleHoldActive = true
                }
            }
        }
    }

    private func cancelPendingLongPressTrigger() {
        longPressTriggerTask?.cancel()
        longPressTriggerTask = nil
    }

    private func triggerTapAction() {
        switch viewModel.state {
        case .listening, .speaking:
            AppHaptics.trigger(.lightTap)
        case .error:
            AppHaptics.trigger(.selection)
        case .connecting, .loading:
            break
        }
        animateInteractionPulse()
        viewModel.handleCircleTap()
    }

    private func triggerLongPressAction(
        viewModel: VoiceChatOverlayViewModel?
    ) -> Bool {
        guard let viewModel, viewModel.state == .listening else { return false }
        AppHaptics.trigger(.selection)
        viewModel.handleCircleLongPressBegan()
        return true
    }

    private func animateInteractionPulse(strength: CGFloat = 1.025) {
        interactionPulse = strength
        withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
            interactionPulse = 1
        }
    }

    private func handleStateChange(
        from oldState: VoiceChatOverlayViewModel.OverlayState,
        to newState: VoiceChatOverlayViewModel.OverlayState
    ) {
        let wasError: Bool = {
            if case .error = oldState { return true }
            return false
        }()
        let isError: Bool = {
            if case .error = newState { return true }
            return false
        }()

        if !wasError && isError {
            AppHaptics.trigger(.error)
        } else if wasError {
            switch newState {
            case .listening, .speaking:
                AppHaptics.trigger(.success)
            case .connecting, .loading, .error:
                break
            }
        }

        motionController.setAudioSource(nil)
        motionController.setAudioLevels(.silent)
        motionController.setState(motionState(for: newState))
        updateMotionAudioSource(for: newState)
    }

    private func updateMotionAudioSource(
        for state: VoiceChatOverlayViewModel.OverlayState
    ) {
        switch state {
        case .listening:
            motionController.setAudioSource(viewModel.inputMotionAudioSource)
        case .speaking:
            motionController.setAudioSource(viewModel.outputMotionAudioSource)
        case .connecting, .loading, .error:
            motionController.setAudioSource(nil)
        }
    }

    private func resetInteractionState() {
        cancelPendingLongPressTrigger()
        isCirclePressed = false
        isCircleHoldActive = false
        didTriggerCircleLongPress = false
        shouldSuppressCircleTapOnEnd = false
        circleGestureCancelled = false
        circlePressOrigin = nil
        pressedCircleBaseSize = nil
        interactionPulse = 1
    }
}
