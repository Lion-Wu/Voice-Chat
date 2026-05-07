//
//  SideMenuContainerViewController.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/02/19.
//

#if os(iOS) || os(tvOS) || os(visionOS)

import SwiftUI
import UIKit

final class SideMenuContainerViewController: UIViewController {

    private let sideMenuWidth: CGFloat = 325
    private let minimumMainContentWidthForPersistentSidebar: CGFloat = 420
    private let menuOpeningAnimationDuration: TimeInterval = 0.42
    private let menuClosingAnimationDuration: TimeInterval = 0.36
    private let reducedMotionMenuAnimationDuration: TimeInterval = 0.16
    private let minimumMenuCompletionDuration: TimeInterval = 0.18
    private let menuSpringDampingRatio: CGFloat = 1.0
    private let menuSpringInitialVelocity: CGFloat = 0
    private let maxMainDimmingAlpha: CGFloat = 0.2

    private var sidebarHostingController: UIHostingController<SidebarRootView>!
    private var mainHostingController: UIHostingController<MainRootView>!
    private let mainDimmingView = UIView()
    private weak var panGestureRecognizer: UIPanGestureRecognizer?

    private var sideMenuHorizontalConstraint: NSLayoutConstraint!
    private var mainHorizontalConstraint: NSLayoutConstraint!
    private var mainBottomConstraint: NSLayoutConstraint!
    private var managedLayoutConstraints: [NSLayoutConstraint] = []

    private var isMenuOpen = false
    private var usesPersistentSidebar = false
    private var startMenuOffset: CGFloat = 0
    private var currentLayoutDirection: UIUserInterfaceLayoutDirection = .leftToRight

    var chatSessionsViewModel: ChatSessionsViewModel!
    var audioManager: GlobalAudioManager!
    var settingsManager: SettingsManager!
    // Speech input manager reference used by embedded SwiftUI views.
    var speechInputManager: SpeechInputManager!
    var voiceOverlayViewModel: VoiceChatOverlayViewModel!
    var errorCenter: AppErrorCenter!

    override func viewDidLoad() {
        super.viewDidLoad()
        currentLayoutDirection = view.effectiveUserInterfaceLayoutDirection
        configureHierarchy()
        configureConstraints()
        configureGestures()
        configureKeyboardHandling()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePersistentSidebarModeIfNeeded()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updatePersistentSidebarModeIfNeeded(for: size.width)
        })
    }

    private var closedMenuOffset: CGFloat {
        currentLayoutDirection == .rightToLeft ? sideMenuWidth : -sideMenuWidth
    }

    private var swiftUILayoutDirection: LayoutDirection {
        currentLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    private func configureHierarchy() {
        let sidebarVC = UIHostingController(rootView: makeSidebarRootView())
        self.sidebarHostingController = sidebarVC

        addChild(sidebarVC)
        view.addSubview(sidebarVC.view)
        sidebarVC.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarVC.didMove(toParent: self)

        let mainVC = UIHostingController(rootView: makeMainRootView())
        self.mainHostingController = mainVC

        addChild(mainVC)
        view.addSubview(mainVC.view)
        mainVC.view.translatesAutoresizingMaskIntoConstraints = false
        mainVC.didMove(toParent: self)
        configureMainDimmingOverlay(on: mainVC.view)
    }

    private func makeSidebarRootView() -> SidebarRootView {
        SidebarRootView(
            layoutDirection: swiftUILayoutDirection,
            chatSessionsViewModel: chatSessionsViewModel,
            voiceOverlayViewModel: voiceOverlayViewModel,
            errorCenter: errorCenter,
            onConversationTap: { [weak self] session in
                guard let self = self else { return }
                self.chatSessionsViewModel.selectedSession = session
                if !self.usesPersistentSidebar {
                    self.toggleMenu(open: false, animated: true)
                }
            },
            onOpenSettings: { [weak self] in
                self?.presentSettings()
            }
        )
    }

    private func makeMainRootView() -> MainRootView {
        MainRootView(
            layoutDirection: swiftUILayoutDirection,
            chatSessionsViewModel: chatSessionsViewModel,
            audioManager: audioManager,
            settingsManager: settingsManager,
            speechInputManager: speechInputManager,
            voiceOverlayViewModel: voiceOverlayViewModel,
            errorCenter: errorCenter,
            onToggleSidebar: { [weak self] in
                guard let self = self else { return }
                self.toggleMenu(open: !self.isMenuOpen, animated: true)
            }
        )
    }

    private func shouldUsePersistentSidebar(for width: CGFloat) -> Bool {
#if os(iOS)
        traitCollection.userInterfaceIdiom == .pad
            && width >= sideMenuWidth + minimumMainContentWidthForPersistentSidebar
#else
        false
#endif
    }

    private func updatePersistentSidebarModeIfNeeded(for width: CGFloat? = nil) {
        let targetWidth = width ?? view.bounds.width
        let shouldPersistSidebar = shouldUsePersistentSidebar(for: targetWidth)
        guard usesPersistentSidebar != shouldPersistSidebar else { return }

        usesPersistentSidebar = shouldPersistSidebar
        // Entering wide iPad layout should reveal the flat sidebar by default;
        // leaving it should return to the compact closed side-menu state.
        isMenuOpen = shouldPersistSidebar
        sidebarHostingController.rootView = makeSidebarRootView()
        mainHostingController.rootView = makeMainRootView()
        configureConstraints()
    }

    private func configureConstraints() {
        guard let sidebarView = sidebarHostingController?.view,
              let mainView = mainHostingController?.view else { return }

        let preservedMenuOpen = isMenuOpen
        let preservedBottomConstant = mainBottomConstraint?.constant ?? 0
        NSLayoutConstraint.deactivate(managedLayoutConstraints)

        if currentLayoutDirection == .rightToLeft {
            sideMenuHorizontalConstraint = sidebarView.rightAnchor.constraint(
                equalTo: view.rightAnchor,
                constant: preservedMenuOpen ? 0 : closedMenuOffset
            )
            mainHorizontalConstraint = mainView.rightAnchor.constraint(
                equalTo: sidebarView.leftAnchor,
                constant: 0
            )
        } else {
            sideMenuHorizontalConstraint = sidebarView.leftAnchor.constraint(
                equalTo: view.leftAnchor,
                constant: preservedMenuOpen ? 0 : closedMenuOffset
            )
            mainHorizontalConstraint = mainView.leftAnchor.constraint(
                equalTo: sidebarView.rightAnchor,
                constant: 0
            )
        }

        var constraints: [NSLayoutConstraint] = [
            sideMenuHorizontalConstraint,
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: sideMenuWidth),
            mainHorizontalConstraint,
            mainView.topAnchor.constraint(equalTo: view.topAnchor)
        ]

        if usesPersistentSidebar {
            if currentLayoutDirection == .rightToLeft {
                constraints.append(mainView.leftAnchor.constraint(equalTo: view.leftAnchor))
            } else {
                constraints.append(mainView.rightAnchor.constraint(equalTo: view.rightAnchor))
            }
        } else {
            constraints.append(mainView.widthAnchor.constraint(equalTo: view.widthAnchor))
        }

        mainBottomConstraint = mainView.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: preservedBottomConstant
        )
        constraints.append(mainBottomConstraint)
        managedLayoutConstraints = constraints

        NSLayoutConstraint.activate(managedLayoutConstraints)

        isMenuOpen = preservedMenuOpen
        updateMenuPresentation(forMenuOffset: sideMenuHorizontalConstraint.constant)
    }

    private func configureGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        panGestureRecognizer = panGesture
        view.addGestureRecognizer(panGesture)
    }

    private func configureKeyboardHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc
    private func handleKeyboardFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }

        let endFrame = endFrameValue.cgRectValue
        let endFrameInView = view.convert(endFrame, from: view.window)
        let overlap = max(0, view.bounds.maxY - endFrameInView.minY)
        mainBottomConstraint.constant = -overlap

        let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveRaw = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
    }

    private func presentSettings() {
        let settingsView = SettingsView(settingsManager: settingsManager)
            .environment(\.layoutDirection, swiftUILayoutDirection)
        let settingsVC = UIHostingController(rootView: settingsView)
        settingsVC.view.semanticContentAttribute = currentLayoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        settingsVC.modalPresentationStyle = .formSheet
        present(settingsVC, animated: true, completion: nil)
    }

    private func configureMainDimmingOverlay(on mainView: UIView) {
        mainDimmingView.translatesAutoresizingMaskIntoConstraints = false
        mainDimmingView.backgroundColor = .black
        mainDimmingView.alpha = 0
        mainDimmingView.isHidden = false
        mainDimmingView.isUserInteractionEnabled = false
        mainDimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleMainDimmingTap)))

        // Keep the dimming view outside UIHostingController.view to avoid breaking SwiftUI view hierarchy.
        view.insertSubview(mainDimmingView, aboveSubview: mainView)
        NSLayoutConstraint.activate([
            mainDimmingView.topAnchor.constraint(equalTo: mainView.topAnchor),
            mainDimmingView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
            mainDimmingView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            mainDimmingView.trailingAnchor.constraint(equalTo: mainView.trailingAnchor)
        ])
    }

    @objc
    private func handleMainDimmingTap() {
        toggleMenu(open: false, animated: true)
    }

    private func menuProgress(forMenuOffset offset: CGFloat) -> CGFloat {
        if currentLayoutDirection == .rightToLeft {
            max(0, min(1, 1 - (offset / sideMenuWidth)))
        } else {
            max(0, min(1, 1 + (offset / sideMenuWidth)))
        }
    }

    private func easedMenuProgress(_ progress: CGFloat) -> CGFloat {
        let clampedProgress = max(0, min(1, progress))
        return clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
    }

    private func updateMenuPresentation(forMenuOffset offset: CGFloat) {
        guard !usesPersistentSidebar else {
            sidebarHostingController?.view.alpha = 1
            mainDimmingView.alpha = 0
            mainDimmingView.isUserInteractionEnabled = false
            return
        }

        let progress = menuProgress(forMenuOffset: offset)
        let easedProgress = easedMenuProgress(progress)
        let alpha = easedProgress * maxMainDimmingAlpha
        sidebarHostingController?.view.alpha = easedProgress
        mainDimmingView.alpha = alpha
        mainDimmingView.isUserInteractionEnabled = alpha > 0.001
    }

    private func menuAnimationDuration(opening: Bool, from currentOffset: CGFloat, to finalOffset: CGFloat) -> TimeInterval {
        if UIAccessibility.isReduceMotionEnabled {
            return reducedMotionMenuAnimationDuration
        }

        let baseDuration = opening ? menuOpeningAnimationDuration : menuClosingAnimationDuration
        let remainingTravel = min(1, abs(finalOffset - currentOffset) / sideMenuWidth)
        return max(minimumMenuCompletionDuration, baseDuration * TimeInterval(remainingTravel))
    }

    private func dismissKeyboardIfNeeded() {
        view.endEditing(true)
    }

    func toggleMenu(open: Bool, animated: Bool) {
        let wasMenuOpen = isMenuOpen
        let shouldTriggerHaptic = (wasMenuOpen != open)
        if !usesPersistentSidebar && (open || wasMenuOpen) {
            dismissKeyboardIfNeeded()
        }

        isMenuOpen = open
        let finalOffset = open ? 0 : closedMenuOffset

        if animated {
            let duration = menuAnimationDuration(
                opening: open,
                from: sideMenuHorizontalConstraint.constant,
                to: finalOffset
            )
            let animations = {
                self.sideMenuHorizontalConstraint.constant = finalOffset
                self.updateMenuPresentation(forMenuOffset: finalOffset)
                self.view.layoutIfNeeded()
            }

            if UIAccessibility.isReduceMotionEnabled {
                UIView.animate(
                    withDuration: duration,
                    delay: 0,
                    options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                    animations: animations
                )
            } else {
                UIView.animate(
                    withDuration: duration,
                    delay: 0,
                    usingSpringWithDamping: menuSpringDampingRatio,
                    initialSpringVelocity: menuSpringInitialVelocity,
                    options: [.beginFromCurrentState, .allowUserInteraction],
                    animations: animations
                )
            }
        } else {
            sideMenuHorizontalConstraint.constant = finalOffset
            updateMenuPresentation(forMenuOffset: finalOffset)
            view.layoutIfNeeded()
        }

        if shouldTriggerHaptic {
            AppHaptics.trigger(.lightTap)
        }
    }

    @objc
    private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard !usesPersistentSidebar else { return }

        let translation = gesture.translation(in: view).x

        switch gesture.state {
        case .began:
            startMenuOffset = sideMenuHorizontalConstraint.constant
        case .changed:
            let newOffset = startMenuOffset + translation
            let minOffset = min(closedMenuOffset, 0)
            let maxOffset = max(closedMenuOffset, 0)
            sideMenuHorizontalConstraint.constant = max(minOffset, min(maxOffset, newOffset))
            updateMenuPresentation(forMenuOffset: sideMenuHorizontalConstraint.constant)
        case .ended, .cancelled:
            let velocityX = gesture.velocity(in: view).x
            let signedVelocity = currentLayoutDirection == .rightToLeft ? -velocityX : velocityX
            let currentOffset = sideMenuHorizontalConstraint.constant
            let shouldOpen: Bool
            if abs(signedVelocity) > 300 {
                shouldOpen = signedVelocity > 0
            } else {
                shouldOpen = currentLayoutDirection == .rightToLeft
                    ? (currentOffset < sideMenuWidth * 0.5)
                    : (currentOffset > -sideMenuWidth * 0.5)
            }
            toggleMenu(open: shouldOpen, animated: true)
        default:
            break
        }
    }

    func updateLayoutDirection(_ layoutDirection: LayoutDirection) {
        let resolvedDirection: UIUserInterfaceLayoutDirection = layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        let semantic: UISemanticContentAttribute = layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight

        view.semanticContentAttribute = semantic
        sidebarHostingController?.view.semanticContentAttribute = semantic
        mainHostingController?.view.semanticContentAttribute = semantic

        guard currentLayoutDirection != resolvedDirection else { return }
        currentLayoutDirection = resolvedDirection
        guard isViewLoaded else { return }

        sidebarHostingController.rootView = makeSidebarRootView()
        mainHostingController.rootView = makeMainRootView()
        configureConstraints()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private struct SidebarRootView: View {
    let layoutDirection: LayoutDirection
    let chatSessionsViewModel: ChatSessionsViewModel
    let voiceOverlayViewModel: VoiceChatOverlayViewModel
    let errorCenter: AppErrorCenter
    let onConversationTap: (ChatSession) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        NavigationStack {
            SidebarView(
                onConversationTap: onConversationTap,
                onOpenSettings: onOpenSettings
            )
            .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.layoutDirection, layoutDirection)
        .environmentObject(chatSessionsViewModel)
        .environmentObject(voiceOverlayViewModel)
        .environmentObject(errorCenter)
    }
}

private struct MainRootView: View {
    let layoutDirection: LayoutDirection
    let chatSessionsViewModel: ChatSessionsViewModel
    let audioManager: GlobalAudioManager
    let settingsManager: SettingsManager
    let speechInputManager: SpeechInputManager
    let voiceOverlayViewModel: VoiceChatOverlayViewModel
    let errorCenter: AppErrorCenter
    let onToggleSidebar: () -> Void

    var body: some View {
        MainContentView(onToggleSidebar: onToggleSidebar)
            .environment(\.layoutDirection, layoutDirection)
            .environmentObject(chatSessionsViewModel)
            .environmentObject(audioManager)
            .environmentObject(settingsManager)
            .environmentObject(speechInputManager)
            .environmentObject(voiceOverlayViewModel)
            .environmentObject(errorCenter)
    }
}

extension SideMenuContainerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else { return true }
        return !usesPersistentSidebar
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

struct SideMenuContainerRepresentable: UIViewControllerRepresentable {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var voiceOverlayViewModel: VoiceChatOverlayViewModel
    @EnvironmentObject var errorCenter: AppErrorCenter
    let speechInputManager: SpeechInputManager

    func makeUIViewController(context: Context) -> SideMenuContainerViewController {
        let vc = SideMenuContainerViewController()
        vc.chatSessionsViewModel = chatSessionsViewModel
        vc.audioManager = audioManager
        vc.settingsManager = settingsManager
        vc.speechInputManager = speechInputManager
        vc.voiceOverlayViewModel = voiceOverlayViewModel
        vc.errorCenter = errorCenter
        vc.updateLayoutDirection(context.environment.layoutDirection)
        return vc
    }

    func updateUIViewController(_ uiViewController: SideMenuContainerViewController, context: Context) {
        uiViewController.updateLayoutDirection(context.environment.layoutDirection)
    }
}

#Preview {
    let audio = GlobalAudioManager()
    let speech = SpeechInputManager()
    let chatSessions = ChatSessionsViewModel(audioManager: audio)
    let overlayVM = VoiceChatOverlayViewModel(
        speechInputManager: speech,
        audioManager: audio,
        errorCenter: AppErrorCenter.shared,
        settingsManager: SettingsManager.shared,
        reachabilityMonitor: ServerReachabilityMonitor.shared
    )

    SideMenuContainerRepresentable(speechInputManager: speech)
        .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
        .environmentObject(chatSessions)
        .environmentObject(audio)
        .environmentObject(SettingsManager.shared)
        .environmentObject(overlayVM)
        .environmentObject(AppErrorCenter.shared)
}

#endif
