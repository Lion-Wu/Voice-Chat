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
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif

    /// Optional callback so the parent can react when the overlay is dismissed.
    var onClose: () -> Void = {}
    var displayStyle: DisplayStyle = .standard

    // Animation state
    @State private var smoothedInputLevel: CGFloat = 0
    @State private var smoothedOutputLevel: CGFloat = 0
    @State private var displayedCircleDiameter: CGFloat = 0
    @State private var displayedCircleLevelScale: CGFloat = 1
    @State private var errorCutoutProgress: CGFloat = 0
    @State private var loadingBreath: CGFloat = 0
    @State private var isLoadingBreathing: Bool = false
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

    private var activeCircleErrorRingWidth: CGFloat {
        #if os(iOS) || os(macOS)
        if viewModel.isVisionCapturePresented {
            return 6
        }
        #endif
        return circleErrorRingWidth
    }

#if os(iOS)
    private var usesCompactVisionCaptureControls: Bool {
        viewModel.isVisionCapturePresented && (horizontalSizeClass == .compact || verticalSizeClass == .compact)
    }
#else
    private var usesCompactVisionCaptureControls: Bool {
        false
    }
#endif

    private var overlayControlPickerMaxWidth: CGFloat {
        if isVisionSceneStyle { return 360 }
        return usesCompactVisionCaptureControls ? 252 : 320
    }

    private var overlayControlHorizontalPadding: CGFloat {
        if isVisionSceneStyle { return 20 }
        return usesCompactVisionCaptureControls ? 10 : 16
    }

    private var overlayControlVerticalPadding: CGFloat {
        if isVisionSceneStyle { return 14 }
        return usesCompactVisionCaptureControls ? 7 : 12
    }

    private var overlayCameraButtonSize: CGFloat {
        usesCompactVisionCaptureControls ? 34 : 38
    }

    private var overlayControlCornerRadius: CGFloat {
        usesCompactVisionCaptureControls ? 18 : 22
    }

    private var compactVisionControlOverlayHeight: CGFloat {
        58
    }

    private var compactVisionTopTrailingReservedWidth: CGFloat {
        52
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
            if !usesCompactVisionCaptureControls {
                bottomControlContainer
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
#if !os(visionOS)
        .overlay(alignment: .bottom) {
            if usesCompactVisionCaptureControls {
                bottomControlContainer
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                    .zIndex(2)
            }
        }
#endif
        .onChange(of: viewModel.state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
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
            #if !os(macOS)
            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    closeButton
                }
                .padding(.top, closeButtonTopPadding)
                .padding(.horizontal, closeButtonHorizontalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .zIndex(3)
            #endif

            #if os(iOS) || os(macOS)
            if viewModel.isVisionCapturePresented {
                inlineVisionLayout
            } else {
                centeredVoiceLayout
            }
            #else
            centeredVoiceLayout
            #endif
        }
    }

    private var centeredVoiceLayout: some View {
        VStack(spacing: 18) {
            voiceControl

            if let message = overlayErrorText {
                reconnectMessage(message)
            }
        }
        .animation(stateAnimation, value: viewModel.state)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

#if os(iOS) || os(macOS)
    private var inlineVisionLayout: some View {
        GeometryReader { proxy in
            let isStacked = proxy.size.width < 720 || proxy.size.height < 560
            let isCompactControls = usesCompactVisionCaptureControls
            let topPadding: CGFloat = isCompactControls ? 6 : (isStacked ? 42 : 70)
            let horizontalPadding: CGFloat = isCompactControls ? 6 : (isStacked ? 18 : 28)
            let bottomPadding: CGFloat = isCompactControls ? 6 : 116
            let voiceBottomPadding: CGFloat = isCompactControls ? (compactVisionControlOverlayHeight + 10) : 10
            let topTrailingReservedWidth: CGFloat = isCompactControls ? compactVisionTopTrailingReservedWidth : 0
            Group {
                if isStacked {
                    ZStack(alignment: .bottom) {
                        VoiceVisionCameraView(
                            viewModel: viewModel,
                            isCompactLayout: isCompactControls,
                            topTrailingReservedWidth: topTrailingReservedWidth
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        inlineVisionVoiceCluster
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, isCompactControls ? 6 : 10)
                            .padding(.bottom, voiceBottomPadding)
                    }
                } else {
                    HStack(spacing: 18) {
                        inlineVisionVoiceCluster
                            .frame(width: 154)

                        VoiceVisionCameraView(viewModel: viewModel, isCompactLayout: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .padding(.top, topPadding)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(stateAnimation, value: viewModel.state)
        }
    }

    private var inlineVisionVoiceCluster: some View {
        VStack(spacing: 8) {
            voiceControl

            if let message = overlayErrorText {
                reconnectMessage(message)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
#endif

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
            let diameter = currentCircleDiameter
            let cutoutProgress = circleCutoutProgress
            VoiceControlCircleShape(
                cutoutProgress: cutoutProgress,
                ringThickness: activeCircleErrorRingWidth
            )
            .fill(circleVisualColor, style: FillStyle(eoFill: true))
            .frame(width: diameter, height: diameter)
            .scaleEffect(currentCircleScale * interactionPulse * circlePressScale)
            .shadow(color: .black.opacity(isCirclePressed ? 0.28 : 0.25), radius: isCirclePressed ? 22 : 16, x: 0, y: isCirclePressed ? 8 : 6)
            .contentShape(Circle())
            .highPriorityGesture(circlePressGesture)
        }
        .frame(width: circleControlFrameSize, height: circleControlFrameSize)
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

    private var bottomControlContainer: some View {
        AppLiquidGlassContainer(spacing: 20) {
            overlayControlStrip
                .padding(.bottom, usesCompactVisionCaptureControls ? 0 : 8)
        }
    }

    private var overlayControlStrip: some View {
        VStack(spacing: 16) {
            HStack(spacing: usesCompactVisionCaptureControls ? 8 : 10) {
                Picker("", selection: Binding(
                    get: { viewModel.selectedLanguage },
                    set: { viewModel.updateLanguage($0) }
                )) {
                    ForEach(viewModel.availableLanguages) { language in
                        Text(language.defaultDisplayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: overlayControlPickerMaxWidth)

#if os(iOS) || os(macOS)
                if viewModel.isVisionCaptureAvailable {
                    Button {
#if os(iOS)
                        AppHaptics.trigger(.selection)
#endif
                        if viewModel.isVisionCapturePresented {
                            viewModel.dismissVisionCapture()
                        } else {
                            viewModel.presentVisionCapture()
                        }
                    } label: {
                        Image(systemName: viewModel.isVisionCapturePresented ? "camera.viewfinder" : "camera.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: overlayCameraButtonSize, height: overlayCameraButtonSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChatTheme.accent)
                    .accessibilityLabel(viewModel.isVisionCapturePresented ? "Close voice vision camera" : "Open voice vision camera")
                }
#endif
            }
            .padding(.horizontal, overlayControlHorizontalPadding)
            .padding(.vertical, overlayControlVerticalPadding)
#if os(visionOS)
            .glassBackgroundEffect(in: Capsule(style: .continuous), displayMode: .always)
#else
            .appChromedContainer(cornerRadius: overlayControlCornerRadius, shadowOpacity: 0.32)
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
        displayedCircleDiameter = circleTargetDiameter(for: viewModel.state)
        displayedCircleLevelScale = circleTargetLevelScale(for: viewModel.state)
        errorCutoutProgress = circleTargetCutoutProgress(for: viewModel.state)
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

    private var currentCircleScale: CGFloat {
        if let pressedCircleScale { return pressedCircleScale }
        return displayedCircleLevelScale * loadingBreathScale
    }

    private var loadingBreathScale: CGFloat {
        1.0 + (0.055 * loadingBreath)
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
        pressedCircleScale = currentCircleScale
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

    // MARK: - Animation helpers

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
        withAnimation(.easeOut(duration: 0.18)) {
            loadingBreath = 0
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
