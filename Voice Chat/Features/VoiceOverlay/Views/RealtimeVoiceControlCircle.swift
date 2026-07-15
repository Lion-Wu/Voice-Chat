//
//  RealtimeVoiceControlCircle.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct RealtimeVoiceControlCircle: View {
    @ObservedObject var viewModel: VoiceChatOverlayViewModel
    var displayStyle: RealtimeVoiceOverlayView.DisplayStyle = .standard
    var externalPulseToken: UUID?

    @Environment(\.colorScheme) private var colorScheme

    @State private var smoothedInputLevel: CGFloat = 0
    @State private var smoothedOutputLevel: CGFloat = 0
    @State private var displayedCircleDiameter: CGFloat = 0
    @State private var displayedCircleLevelScale: CGFloat = 1
    @State private var errorCutoutProgress: CGFloat = 0
    @State private var isCirclePressed: Bool = false
    @State private var isCircleHoldActive: Bool = false
    @State private var didTriggerCircleLongPress: Bool = false
    @State private var shouldSuppressCircleTapOnEnd: Bool = false
    @State private var circleGestureCancelled: Bool = false
    @State private var circlePressOrigin: CGPoint?
    @State private var pressedCircleBaseSize: CGFloat?
    @State private var pressedCircleScale: CGFloat?
    @State private var longPressTriggerTask: Task<Void, Never>?
    @State private var interactionPulse: CGFloat = 1

    private let stateAnimation = Animation.spring(response: 0.34, dampingFraction: 0.92, blendDuration: 0.16)
    private let cutoutAnimation = Animation.timingCurve(0.78, 0.0, 0.18, 1.0, duration: 0.34)
    private let circlePressInAnimation = Animation.easeOut(duration: 0.12)
    private let circlePressOutAnimation = Animation.easeOut(duration: 0.15)
    private let levelScaleAnimation = Animation.interpolatingSpring(stiffness: 220, damping: 32)
    private let levelSmoothingFactor: CGFloat = 0.40
    private let scaleUpdateEpsilon: CGFloat = 0.0012
    private let circleLongPressDuration: Double = 0.38
    private let circleLongPressMaximumDistance: CGFloat = 42
    private let circleErrorRingWidth: CGFloat = 14
    private let inputLevelScaleAmplitude: CGFloat = 0.38
    private let outputLevelScaleAmplitude: CGFloat = 0.34

    private var circleBaseColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var circleCutoutProgress: CGFloat {
        min(1, max(0, errorCutoutProgress))
    }

    private var circleVisualColor: Color {
        circleBaseColor.opacity(Double(circleVisualOpacity))
    }

    private var circleVisualOpacity: CGFloat {
        let errorOpacity: CGFloat = colorScheme == .dark ? 0.55 : 0.28
        return 1 - ((1 - errorOpacity) * circleCutoutProgress)
    }

    private var overlayErrorText: String? {
        if case let .error(message) = viewModel.state {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private var accessibilityValue: String {
        switch viewModel.state {
        case .listening:
            String(localized: "Listening")
        case .speaking:
            String(localized: "Speaking")
        case .loading:
            String(localized: "Connecting")
        case .error:
            String(localized: "Error")
        }
    }

    private var accessibilityHint: String {
        if overlayErrorText != nil {
            return String(localized: "Double-tap to reconnect.")
        }
        if viewModel.state == .loading {
            return String(localized: "Wait for the voice session to finish connecting.")
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
        return isVisionSceneStyle ? 328 : 280
    }

    private var isVisionSceneStyle: Bool {
        #if os(visionOS)
        displayStyle == .visionScene
        #else
        false
        #endif
    }

    private var activeCircleErrorRingWidth: CGFloat {
        #if os(iOS) || os(macOS)
        if viewModel.isVisionCapturePresented {
            return 6
        }
        #endif
        return circleErrorRingWidth
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: viewModel.state != .loading)) { context in
            ZStack {
                let diameter = currentCircleDiameter
                let cutoutProgress = circleCutoutProgress
                VoiceControlCircleShape(
                    cutoutProgress: cutoutProgress,
                    ringThickness: activeCircleErrorRingWidth
                )
                .fill(circleVisualColor, style: FillStyle(eoFill: true))
                .frame(width: diameter, height: diameter)
                .scaleEffect(currentCircleScale(at: context.date) * interactionPulse * circlePressScale)
                .shadow(color: .black.opacity(isCirclePressed ? 0.28 : 0.25), radius: isCirclePressed ? 22 : 16, x: 0, y: isCirclePressed ? 8 : 6)
                .contentShape(Circle())
                .highPriorityGesture(circlePressGesture)
            }
            .frame(width: circleControlFrameSize, height: circleControlFrameSize)
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
            configureInitialState()
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
        #if os(iOS) || os(macOS)
        .onChange(of: viewModel.isVisionCapturePresented) { _, _ in
            handleVisionCapturePresentationChange()
        }
        #endif
        .onReceive(viewModel.inputLevelPublisher) { newLevel in
            handleInputLevelChange(newLevel)
        }
        .onReceive(viewModel.outputLevelPublisher) { newLevel in
            handleOutputLevelChange(newLevel)
        }
    }

    private func configureInitialState() {
        displayedCircleDiameter = circleTargetDiameter(for: viewModel.state)
        displayedCircleLevelScale = circleTargetLevelScale(for: viewModel.state)
        errorCutoutProgress = circleTargetCutoutProgress(for: viewModel.state)
    }

    private func teardown() {
        cancelPendingLongPressTrigger()
        resetInteractionState()
    }

    private var circlePressScale: CGFloat {
        if isCircleHoldActive { return 1.10 }
        return isCirclePressed ? 1.015 : 1.0
    }

    private var circleControlFrameSize: CGFloat {
        listeningBaseSize
    }

    private var currentCircleDiameter: CGFloat {
        if let pressedCircleBaseSize { return pressedCircleBaseSize }
        return effectiveDisplayedCircleDiameter
    }

    private var effectiveDisplayedCircleDiameter: CGFloat {
        if displayedCircleDiameter > 0 { return displayedCircleDiameter }
        return circleTargetDiameter(for: viewModel.state)
    }

    private func currentCircleScale(at date: Date) -> CGFloat {
        if let pressedCircleScale { return pressedCircleScale }
        return displayedCircleLevelScale * loadingBreathScale(at: date)
    }

    private func loadingBreathScale(at date: Date) -> CGFloat {
        guard viewModel.state == .loading else { return 1 }
        let period = 1.84
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        let wave = (1 - cos(phase * 2 * Double.pi)) / 2
        return 1 + (0.055 * CGFloat(wave))
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
        pressedCircleBaseSize = currentCircleDiameter
        pressedCircleScale = currentCircleScale(at: Date())
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
        guard isCirclePressed || pressedCircleBaseSize != nil || pressedCircleScale != nil else { return }
        withAnimation(circlePressOutAnimation) {
            isCirclePressed = false
            isCircleHoldActive = false
            pressedCircleBaseSize = nil
            pressedCircleScale = nil
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
        case .loading:
            break
        }
        animateInteractionPulse()
        viewModel.handleCircleTap()
    }

    private func triggerLongPressAction(viewModel: VoiceChatOverlayViewModel?) -> Bool {
        guard let viewModel, viewModel.state == .listening else { return false }
        AppHaptics.trigger(.selection)
        viewModel.handleCircleLongPressBegan()
        return true
    }

    private func animateInteractionPulse(strength: CGFloat = 1.025) {
        interactionPulse = strength
        withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
            interactionPulse = 1.0
        }
    }

    private func circleTargetDiameter(for state: VoiceChatOverlayViewModel.OverlayState) -> CGFloat {
        switch state {
        case .listening:
            return listeningBaseSize
        case .speaking, .loading, .error:
            return defaultBaseSize
        }
    }

    private func circleTargetLevelScale(for state: VoiceChatOverlayViewModel.OverlayState) -> CGFloat {
        switch state {
        case .listening:
            return levelScale(for: smoothedInputLevel, amplitude: inputLevelScaleAmplitude)
        case .speaking:
            return levelScale(for: smoothedOutputLevel, amplitude: outputLevelScaleAmplitude)
        case .loading, .error:
            return 1.0
        }
    }

    private func circleTargetCutoutProgress(for state: VoiceChatOverlayViewModel.OverlayState) -> CGFloat {
        if case .error = state { return 1 }
        return 0
    }

    private func levelScale(for level: CGFloat, amplitude: CGFloat) -> CGFloat {
        let responsiveLevel = pow(min(1, max(0, level)), 0.55)
        return 1.0 + amplitude * responsiveLevel
    }

    private func handleStateChange(from oldState: VoiceChatOverlayViewModel.OverlayState, to newState: VoiceChatOverlayViewModel.OverlayState) {
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
            case .loading, .error:
                break
            }
        }

        switch newState {
        case .listening:
            smoothedOutputLevel *= 0.35
        case .speaking:
            smoothedInputLevel *= 0.35
        case .loading, .error:
            smoothedInputLevel = 0
            smoothedOutputLevel = 0
        }

        withAnimation(stateAnimation) {
            displayedCircleDiameter = circleTargetDiameter(for: newState)
            displayedCircleLevelScale = circleTargetLevelScale(for: newState)
        }
        withAnimation(cutoutAnimation) {
            errorCutoutProgress = circleTargetCutoutProgress(for: newState)
        }
    }

    #if os(iOS) || os(macOS)
    private func handleVisionCapturePresentationChange() {
        endCirclePressVisualState()
        withAnimation(stateAnimation) {
            displayedCircleDiameter = circleTargetDiameter(for: viewModel.state)
            displayedCircleLevelScale = circleTargetLevelScale(for: viewModel.state)
        }
    }
    #endif

    private func handleInputLevelChange(_ newLevel: Double) {
        guard viewModel.state == .listening else { return }
        smoothedInputLevel = smoothedLevel(current: smoothedInputLevel, target: normalizedLevel(newLevel))
        updateDisplayedLevelScaleIfNeeded(circleTargetLevelScale(for: .listening))
    }

    private func handleOutputLevelChange(_ newLevel: Double) {
        guard viewModel.state == .speaking else { return }
        smoothedOutputLevel = smoothedLevel(current: smoothedOutputLevel, target: normalizedLevel(newLevel))
        updateDisplayedLevelScaleIfNeeded(circleTargetLevelScale(for: .speaking))
    }

    private func normalizedLevel(_ rawLevel: Double) -> CGFloat {
        let clamped = CGFloat(min(1.0, max(0.0, rawLevel)))
        let noiseFloor: CGFloat = 0.03
        guard clamped > noiseFloor else { return 0 }
        return (clamped - noiseFloor) / (1 - noiseFloor)
    }

    private func smoothedLevel(current: CGFloat, target: CGFloat) -> CGFloat {
        current + (target - current) * levelSmoothingFactor
    }

    private func updateDisplayedLevelScaleIfNeeded(_ scale: CGFloat) {
        guard abs(scale - displayedCircleLevelScale) >= scaleUpdateEpsilon else { return }
        withAnimation(levelScaleAnimation) {
            displayedCircleLevelScale = scale
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
        pressedCircleScale = nil
        interactionPulse = 1
        smoothedInputLevel = 0
        smoothedOutputLevel = 0
        displayedCircleDiameter = 0
        displayedCircleLevelScale = 1
        errorCutoutProgress = 0
    }
}

private struct VoiceControlCircleShape: Shape {
    var cutoutProgress: CGFloat
    var ringThickness: CGFloat

    var animatableData: CGFloat {
        get { cutoutProgress }
        set { cutoutProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let outer = CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )
        let progress = min(1, max(0, cutoutProgress))
        let innerSide = max(0, side - ringThickness * 2) * progress
        let inner = CGRect(
            x: rect.midX - innerSide / 2,
            y: rect.midY - innerSide / 2,
            width: innerSide,
            height: innerSide
        )

        var path = Path()
        path.addEllipse(in: outer)
        if innerSide > 0 {
            path.addEllipse(in: inner)
        }
        return path
    }
}
