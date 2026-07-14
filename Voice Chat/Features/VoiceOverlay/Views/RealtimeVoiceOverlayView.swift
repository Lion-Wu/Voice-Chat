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
    @State private var bottomControlHeight: CGFloat = 0

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

    private var shouldShowRealtimeAssistantPanel: Bool {
        guard let snapshot = viewModel.realtimeAssistantSnapshot else { return false }
        return !snapshot.toolActivities.isEmpty || !snapshot.toolActivityPlacements.isEmpty
    }

    private var hasAssistantStatusContent: Bool {
        shouldShowRealtimeAssistantPanel || overlayErrorText != nil
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomControlContainer
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: VoiceOverlayBottomControlHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
#endif
        .overlay(alignment: .bottom) {
            errorNoticeStack
                .padding(.bottom, isVisionSceneStyle ? 176 : bottomControlHeight + 8)
        }
        .onPreferenceChange(VoiceOverlayBottomControlHeightPreferenceKey.self) { height in
            bottomControlHeight = height
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
            closeButton
                .padding(.top, closeButtonTopPadding)
                .padding(.horizontal, closeButtonHorizontalPadding)
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
        .animation(stateAnimation, value: viewModel.isVisionCapturePresented)
        .animation(stateAnimation, value: shouldShowRealtimeAssistantPanel)
    }

    private var centeredVoiceLayout: some View {
        GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width - 32)
            let availableHeight = max(0, proxy.size.height - 24)
            let usesSideBySideLayout = hasAssistantStatusContent
                && availableWidth >= 700
                && availableWidth > availableHeight * 1.22
            let sideColumnWidth = min(440, max(300, availableWidth * 0.38))
            let sideColumnHeight = min(360, availableHeight)
            let sideSpacing = min(36, max(24, availableWidth * 0.03))

            Group {
                if usesSideBySideLayout {
                    HStack(spacing: sideSpacing) {
                        voiceControl

                        assistantStatusColumn(
                            maxWidth: sideColumnWidth,
                            maxHeight: sideColumnHeight
                        )
                    }
                    .frame(maxWidth: min(900, availableWidth))
                } else {
                    VStack(spacing: 18) {
                        voiceControl

                        if hasAssistantStatusContent {
                            assistantStatusColumn(
                                maxWidth: min(620, availableWidth),
                                maxHeight: min(280, max(120, availableHeight * 0.38))
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .animation(stateAnimation, value: viewModel.state)
    }

#if os(iOS) || os(macOS)
    private var inlineVisionLayout: some View {
        GeometryReader { proxy in
            let isCompactControls = usesCompactVisionCaptureControls
            let horizontalLayout = proxy.size.width >= 700 || proxy.size.width > proxy.size.height * 1.12
            let outerPadding: CGFloat = isCompactControls ? 8 : 18
            let regionSpacing: CGFloat = isCompactControls ? 10 : 16

            Group {
                if horizontalLayout {
                    HStack(spacing: regionSpacing) {
                        VoiceVisionCameraView(viewModel: viewModel, isCompactLayout: isCompactControls)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        inlineVisionActivityColumn(
                            maxWidth: min(360, max(250, proxy.size.width * 0.34)),
                            maxHeight: max(120, proxy.size.height - outerPadding * 2)
                        )
                        .frame(width: min(360, max(250, proxy.size.width * 0.34)))
                    }
                } else {
                    VStack(spacing: regionSpacing) {
                        VoiceVisionCameraView(viewModel: viewModel, isCompactLayout: isCompactControls)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        inlineVisionActivityRow(
                            maxWidth: max(0, proxy.size.width - outerPadding * 2),
                            maxHeight: shouldShowRealtimeAssistantPanel ? 190 : 116
                        )
                    }
                }
            }
            .padding(outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(stateAnimation, value: viewModel.state)
        }
    }

    private func inlineVisionActivityColumn(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            voiceControl

            if hasAssistantStatusContent {
                assistantStatusColumn(
                    maxWidth: maxWidth,
                    maxHeight: min(300, max(100, maxHeight - 132))
                )
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .center)
    }

    private func inlineVisionActivityRow(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        HStack(spacing: 12) {
            voiceControl

            if hasAssistantStatusContent {
                assistantStatusColumn(
                    maxWidth: max(0, maxWidth - 120),
                    maxHeight: maxHeight
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .center)
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

                if hasAssistantStatusContent {
                    assistantStatusColumn(maxWidth: 620, maxHeight: 280)
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

    private func assistantStatusColumn(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            realtimeAssistantPanel(maxWidth: maxWidth, maxHeight: maxHeight)
                .layoutPriority(0)

            if let message = overlayErrorText {
                reconnectMessage(message)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
    }

    @ViewBuilder
    private func realtimeAssistantPanel(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        if shouldShowRealtimeAssistantPanel,
           let snapshot = viewModel.realtimeAssistantSnapshot {
            RealtimeVoiceAssistantPanel(
                snapshot: snapshot,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                onAuthorizeTool: { requestID, allowed in
                    viewModel.resolveRealtimeVoiceToolAuthorization(requestID: requestID, allowed: allowed)
                }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
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
        }
        .padding(.horizontal, usesCompactVisionCaptureControls ? 8 : 16)
        .padding(.top, 6)
        .padding(.bottom, usesCompactVisionCaptureControls ? 4 : 8)
    }

    @ViewBuilder
    private var errorNoticeStack: some View {
        if !errorCenter.notices.isEmpty {
            ErrorNoticeStack(
                notices: errorCenter.notices,
                onDismiss: { notice in
                    errorCenter.dismiss(notice)
                    viewModel.dismissErrorMessage()
                }
            )
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

private struct VoiceOverlayBottomControlHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct RealtimeVoiceAssistantPanel: View {
    let snapshot: RealtimeVoiceAssistantSnapshot
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let onAuthorizeTool: (String, Bool) -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            activityBubble
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                activityBubble
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
    }

    private var activityBubble: some View {
        ToolActivityBubble(
            activities: displayedActivities,
            maxBubbleWidth: maxWidth,
            isEmbeddedInMessage: true,
            fillsAvailableWidth: true,
            developerModeEnabled: false,
            onAuthorize: onAuthorizeTool
        )
        .frame(maxWidth: maxWidth)
    }

    private var displayedActivities: [ChatToolActivity] {
        var activities = snapshot.toolActivityPlacements.map(\.activity)
        for activity in snapshot.toolActivities {
            if let index = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[index] = activity
            } else {
                activities.append(activity)
            }
        }
        var placementOrder: [String: Int] = [:]
        for (index, placement) in snapshot.toolActivityPlacements.enumerated() where placementOrder[placement.id] == nil {
            placementOrder[placement.id] = index
        }
        return activities.sorted {
            let lhs = placementOrder[$0.id] ?? Int.max
            let rhs = placementOrder[$1.id] ?? Int.max
            if lhs == rhs {
                return $0.id < $1.id
            }
            return lhs < rhs
        }
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
