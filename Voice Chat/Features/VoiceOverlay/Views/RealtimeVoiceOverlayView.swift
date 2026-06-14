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

    @State private var voiceControlPulseToken = UUID()

    private let stateAnimation = Animation.spring(response: 0.34, dampingFraction: 0.92, blendDuration: 0.16)

    private var circleBaseColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var overlayErrorText: String? {
        if case let .error(message) = viewModel.state {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
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
        .onDisappear {
            viewModel.handleViewDisappear()
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
        RealtimeVoiceControlCircle(
            viewModel: viewModel,
            displayStyle: displayStyle,
            externalPulseToken: voiceControlPulseToken
        )
    }

    private func reconnectMessage(_ message: String) -> some View {
        Button {
            triggerReconnectAction()
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

    private func closeOverlay() {
        viewModel.dismiss()
        onClose()
    }

    private func triggerReconnectAction() {
        AppHaptics.trigger(.selection)
        voiceControlPulseToken = UUID()
        viewModel.handleCircleTap()
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
