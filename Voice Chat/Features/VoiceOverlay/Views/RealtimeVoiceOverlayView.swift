//
//  RealtimeVoiceOverlayView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

struct RealtimeVoiceOverlayView: View {
    enum DisplayStyle {
        case standard
        case visionScene
    }

    @ObservedObject var viewModel: VoiceChatOverlayViewModel
    @EnvironmentObject var errorCenter: AppErrorCenter
    @Environment(\.colorScheme) private var colorScheme

    /// Optional callback so the parent can react when the overlay is dismissed.
    var onClose: () -> Void = {}
    var displayStyle: DisplayStyle = .standard

    // Animation state
    @State private var smoothedInputLevel: CGFloat = 0
    @State private var smoothedOutputLevel: CGFloat = 0
    @State private var displayedScale: CGFloat = 1
    @State private var loadingBreath: CGFloat = 0
    @State private var isLoadingBreathing: Bool = false
    @State private var isCirclePressed: Bool = false
    @State private var didTriggerCircleLongPress: Bool = false
    @State private var circleGestureCancelled: Bool = false
    @State private var circlePressOrigin: CGPoint?
    @State private var longPressTriggerTask: Task<Void, Never>?
    @State private var interactionPulse: CGFloat = 1

    private let stateAnimation = Animation.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.2)
    private let circlePressInAnimation = Animation.easeOut(duration: 0.12)
    private let circlePressOutAnimation = Animation.easeOut(duration: 0.15)
    private let levelScaleAnimation = Animation.interpolatingSpring(stiffness: 245, damping: 26)
    private let levelSmoothingFactor: CGFloat = 0.34
    private let scaleUpdateEpsilon: CGFloat = 0.0012
    private let circleLongPressDuration: Double = 0.38
    private let circleLongPressMaximumDistance: CGFloat = 42

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

    private var voiceControlAccessibilityValue: String {
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

    private var voiceControlAccessibilityHint: String {
        if overlayErrorText != nil {
            return String(localized: "Double-tap to reconnect.")
        }
        if viewModel.state == .loading {
            return String(localized: "Wait for the voice session to finish connecting.")
        }
        return String(localized: "Double-tap to control realtime voice. Use the Hold to talk action for push-to-talk.")
    }

    private var defaultBaseSize: CGFloat {
        isVisionSceneStyle ? 236 : 200
    }

    private var listeningBaseSize: CGFloat {
        isVisionSceneStyle ? 328 : 280
    }

    private var isVisionSceneStyle: Bool {
        #if os(visionOS)
        displayStyle == .visionScene
        #else
        false
        #endif
    }

    private var closeButtonTopPadding: CGFloat {
        isVisionSceneStyle ? 34 : 8
    }

    private var closeButtonHorizontalPadding: CGFloat {
        isVisionSceneStyle ? 34 : 8
    }

    private var ornamentBottomPadding: CGFloat {
        isVisionSceneStyle ? 24 : 12
    }

    private var errorNoticeBottomPadding: CGFloat {
        isVisionSceneStyle ? 176 : 12
    }

    private var visionContentBottomInset: CGFloat {
        isVisionSceneStyle ? 104 : 0
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
            contentLayout
        }
        .onAppear {
            configureInitialState()
        }
        .onDisappear {
            teardown()
        }
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
            overlayControlStrip
                .padding(.bottom, ornamentBottomPadding)
        }
#else
        .safeAreaInset(edge: .bottom) {
            AppLiquidGlassContainer(spacing: 20) {
                overlayControlStrip
                    .padding(.bottom, 8)
            }
        }
#endif
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
                .padding(.bottom, errorNoticeBottomPadding)
                .zIndex(0)
            }
        }
        .onChange(of: viewModel.state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
        .onReceive(viewModel.inputLevelPublisher) { newLevel in
            handleInputLevelChange(newLevel)
        }
        .onReceive(viewModel.outputLevelPublisher) { newLevel in
            handleOutputLevelChange(newLevel)
        }
    }

    @ViewBuilder
    private var contentLayout: some View {
        if isVisionSceneStyle {
            visionSceneLayout
        } else {
            standardLayout
        }
    }

    private var standardLayout: some View {
        ZStack {
            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    closeButton
                }
                .padding(.top, closeButtonTopPadding)
                .padding(.horizontal, closeButtonHorizontalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(spacing: 18) {
                voiceControl

                if let message = overlayErrorText {
                    reconnectMessage(message)
                }
            }
            .animation(stateAnimation, value: viewModel.state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var visionSceneLayout: some View {
        #if os(visionOS)
        ZStack {
            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    closeButton
                }
                .padding(.top, closeButtonTopPadding)
                .padding(.horizontal, closeButtonHorizontalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(spacing: 18) {
                voiceControl

                if let message = overlayErrorText {
                    reconnectMessage(message)
                }
            }
            .animation(stateAnimation, value: viewModel.state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.bottom, visionContentBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(stateAnimation, value: viewModel.state)
        #else
        standardLayout
        #endif
    }

    private var voiceControl: some View {
        ZStack {
            let baseSize = currentCircleBaseSize
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
            .scaleEffect(currentCircleScale * interactionPulse * circlePressScale)
            .shadow(color: .black.opacity(isCirclePressed ? 0.28 : 0.25), radius: isCirclePressed ? 22 : 16, x: 0, y: isCirclePressed ? 8 : 6)
            .contentShape(Circle())
            .highPriorityGesture(circlePressGesture)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Realtime voice control")
        .accessibilityValue(voiceControlAccessibilityValue)
        .accessibilityHint(voiceControlAccessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            triggerTapAction()
        }
        .accessibilityAction(named: Text("Hold to talk")) {
            viewModel.performHoldToTalkAccessibilityAction()
        }
    }

    private func reconnectMessage(_ message: String) -> some View {
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
            .appChromedContainer(cornerRadius: 14, tint: .red.opacity(0.06), interactive: true, shadowOpacity: 0.3)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var overlayControlStrip: some View {
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
            .frame(maxWidth: isVisionSceneStyle ? 360 : 320)
            .padding(.horizontal, isVisionSceneStyle ? 20 : 16)
            .padding(.vertical, isVisionSceneStyle ? 14 : 12)
#if os(visionOS)
            .glassBackgroundEffect(in: Capsule(style: .continuous), displayMode: .always)
#else
            .appChromedContainer(cornerRadius: 22, shadowOpacity: 0.32)
#endif
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var closeButton: some View {
#if os(iOS) || os(tvOS)
        if #available(iOS 26.0, tvOS 26.0, *) {
            Button {
                closeOverlay()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .labelStyle(.iconOnly)
            .accessibilityLabel("Close realtime voice overlay")
        } else {
            legacyCloseButton
        }
#else
        legacyCloseButton
#endif
    }

    private var legacyCloseButton: some View {
        Button {
            closeOverlay()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(circleBaseColor.opacity(0.92))
                .frame(width: 18, height: 18)
                .frame(width: closeButtonSize, height: closeButtonSize)
                .contentShape(Circle())
                .appChromedContainer(
                    cornerRadius: closeButtonSize * 0.5,
                    tint: colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.04),
                    interactive: true,
                    shadowOpacity: 0.35
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close realtime voice overlay")
    }

    private var closeButtonSize: CGFloat {
        AppChromeMetrics.floatingCloseButtonSize
    }

    // MARK: - Lifecycle helpers

    private func configureInitialState() {
        displayedScale = circleTargetScale(for: viewModel.state)
        if viewModel.state == .loading {
            startLoadingBreathIfNeeded()
        }
    }

    private func teardown() {
        cancelPendingLongPressTrigger()
        stopLoadingBreath()
        resetInteractionState()
        viewModel.handleViewDisappear()
    }

    private func closeOverlay() {
        viewModel.dismiss()
        onClose()
    }

    private var circlePressScale: CGFloat {
        isCirclePressed ? 1.12 : 1.0
    }

    private var currentCircleBaseSize: CGFloat {
        // Keep the pressed-down shape stable while holding to avoid a visible size snap
        // when state transitions happen under the finger.
        if isCirclePressed {
            return listeningBaseSize
        }
        return (viewModel.state == .listening) ? listeningBaseSize : defaultBaseSize
    }

    private var currentCircleScale: CGFloat {
        if viewModel.state == .loading {
            return 0.95 + (0.09 * loadingBreath)
        }
        return displayedScale
    }

    private var circlePressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
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
        cancelPendingLongPressTrigger()

        if didTriggerCircleLongPress {
            viewModel.handleCircleLongPressEnded()
            didTriggerCircleLongPress = false
        }

        guard isCirclePressed else { return }
        withAnimation(circlePressOutAnimation) {
            isCirclePressed = false
        }
    }

    private func handleCircleDragEnded() {
        cancelPendingLongPressTrigger()

        if isCirclePressed {
            withAnimation(circlePressOutAnimation) {
                isCirclePressed = false
            }
        }

        if didTriggerCircleLongPress {
            viewModel.handleCircleLongPressEnded()
        } else if !circleGestureCancelled {
            triggerTapAction()
        }

        didTriggerCircleLongPress = false
        circleGestureCancelled = false
        circlePressOrigin = nil
    }

    private func beginCirclePress(at start: CGPoint) {
        circlePressOrigin = start
        circleGestureCancelled = false
        didTriggerCircleLongPress = false
        withAnimation(circlePressInAnimation) {
            isCirclePressed = true
        }
        schedulePendingLongPressTrigger()
    }

    private func schedulePendingLongPressTrigger() {
        cancelPendingLongPressTrigger()
        longPressTriggerTask = Task { @MainActor in
            let delay = UInt64(circleLongPressDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard isCirclePressed else { return }
            guard !circleGestureCancelled else { return }
            guard !didTriggerCircleLongPress else { return }
            didTriggerCircleLongPress = true
            triggerLongPressAction(viewModel: viewModel)
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

    private func triggerLongPressAction(viewModel: VoiceChatOverlayViewModel?) {
        guard viewModel?.state == .listening else { return }
        AppHaptics.trigger(.selection)
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
            return 1.0 + 0.30 * smoothedInputLevel
        case .speaking:
            return 1.0 + 0.30 * smoothedOutputLevel
        case .loading:
            return 0.95
        case .error:
            return 1.0
        }
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

        if newState == .loading {
            startLoadingBreathIfNeeded()
        } else {
            stopLoadingBreath()
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

        displayedScale = circleTargetScale(for: newState)
    }

    private func handleInputLevelChange(_ newLevel: Double) {
        guard viewModel.state == .listening else { return }
        smoothedInputLevel = smoothedLevel(current: smoothedInputLevel, target: normalizedLevel(newLevel))
        updateDisplayedScaleIfNeeded(circleTargetScale(for: .listening))
    }

    private func handleOutputLevelChange(_ newLevel: Double) {
        guard viewModel.state == .speaking else { return }
        smoothedOutputLevel = smoothedLevel(current: smoothedOutputLevel, target: normalizedLevel(newLevel))
        updateDisplayedScaleIfNeeded(circleTargetScale(for: .speaking))
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

    private func updateDisplayedScaleIfNeeded(_ scale: CGFloat) {
        guard abs(scale - displayedScale) >= scaleUpdateEpsilon else { return }
        withAnimation(levelScaleAnimation) {
            displayedScale = scale
        }
    }

    private func startLoadingBreathIfNeeded() {
        guard !isLoadingBreathing else { return }
        isLoadingBreathing = true
        loadingBreath = 0
        withAnimation(.easeInOut(duration: 0.92).repeatForever(autoreverses: true)) {
            loadingBreath = 1
        }
    }

    private func stopLoadingBreath() {
        guard isLoadingBreathing || loadingBreath != 0 else { return }
        isLoadingBreathing = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            loadingBreath = 0
        }
    }

    private func resetInteractionState() {
        cancelPendingLongPressTrigger()
        isCirclePressed = false
        didTriggerCircleLongPress = false
        circleGestureCancelled = false
        circlePressOrigin = nil
        interactionPulse = 1
        smoothedInputLevel = 0
        smoothedOutputLevel = 0
        displayedScale = 1
    }
}

#Preview {
    let speechManager = SpeechInputManager()
    let overlayVM = VoiceChatOverlayViewModel(
        speechInputManager: speechManager,
        audioManager: GlobalAudioManager.shared,
        errorCenter: AppErrorCenter.shared,
        settingsManager: SettingsManager.shared,
        reachabilityMonitor: ServerReachabilityMonitor.shared
    )

    RealtimeVoiceOverlayView(viewModel: overlayVM)
        .environmentObject(AppErrorCenter.shared)
}
