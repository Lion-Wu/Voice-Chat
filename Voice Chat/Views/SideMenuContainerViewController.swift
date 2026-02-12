//
//  SideMenuContainerViewController.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/02/19.
//

#if os(iOS) || os(tvOS)

import SwiftUI
import UIKit

final class SideMenuContainerViewController: UIViewController {

    private let sideMenuWidth: CGFloat = 325
    private let menuAnimationDuration: TimeInterval = 0.22
    private let maxMainDimmingAlpha: CGFloat = 0.2

    private var sidebarHostingController: UIViewController!
    private var mainHostingController: UIViewController!
    private let mainDimmingView = UIView()

    private var sideMenuLeadingConstraint: NSLayoutConstraint!
    private var mainLeftConstraint: NSLayoutConstraint!
    private var mainBottomConstraint: NSLayoutConstraint!

    private var isMenuOpen = false
    private var startMenuLeading: CGFloat = 0

    var chatSessionsViewModel: ChatSessionsViewModel!
    var audioManager: GlobalAudioManager!
    var settingsManager: SettingsManager!
    // Speech input manager reference used by embedded SwiftUI views.
    var speechInputManager: SpeechInputManager!
    var voiceOverlayViewModel: VoiceChatOverlayViewModel!
    var errorCenter: AppErrorCenter!

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureConstraints()
        configureGestures()
        configureKeyboardHandling()
    }

    private func configureHierarchy() {
        let sidebarContent = SidebarView(
            onConversationTap: { [weak self] session in
                self?.chatSessionsViewModel.selectedSession = session
                self?.toggleMenu(open: false, animated: true)
            },
            onOpenSettings: { [weak self] in
                self?.presentSettings()
            }
        )
        .environmentObject(chatSessionsViewModel)
        .environmentObject(voiceOverlayViewModel)
        .environmentObject(errorCenter)

        let sidebarView: AnyView
        if #available(iOS 16, tvOS 16, *) {
            sidebarView = AnyView(
                NavigationStack {
                    sidebarContent
                        .toolbar(.hidden, for: .navigationBar)
                }
            )
        } else {
            sidebarView = AnyView(
                NavigationView {
                    sidebarContent
                        .navigationBarHidden(true)
                }
                .navigationViewStyle(.stack)
            )
        }

        let sidebarVC = UIHostingController(rootView: sidebarView)
        self.sidebarHostingController = sidebarVC

        addChild(sidebarVC)
        view.addSubview(sidebarVC.view)
        sidebarVC.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarVC.didMove(toParent: self)

        let mainView = MainContentView(
            onToggleSidebar: { [weak self] in
                guard let self = self else { return }
                self.toggleMenu(open: !self.isMenuOpen, animated: true)
            }
        )
        .environmentObject(chatSessionsViewModel)
        .environmentObject(audioManager)
        .environmentObject(settingsManager)
        // Pass along the shared speech input manager.
        .environmentObject(speechInputManager)
        .environmentObject(voiceOverlayViewModel)
        .environmentObject(errorCenter)

        let mainVC = UIHostingController(rootView: mainView)
        self.mainHostingController = mainVC

        addChild(mainVC)
        view.addSubview(mainVC.view)
        mainVC.view.translatesAutoresizingMaskIntoConstraints = false
        mainVC.didMove(toParent: self)
        configureMainDimmingOverlay(on: mainVC.view)
    }

    private func configureConstraints() {
        guard let sidebarView = sidebarHostingController?.view,
              let mainView = mainHostingController?.view else { return }

        sideMenuLeadingConstraint = sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -sideMenuWidth)
        NSLayoutConstraint.activate([
            sideMenuLeadingConstraint,
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: sideMenuWidth)
        ])

        mainLeftConstraint = mainView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: 0)
        var mainConstraints: [NSLayoutConstraint] = [
            mainLeftConstraint,
            mainView.topAnchor.constraint(equalTo: view.topAnchor),
            mainView.widthAnchor.constraint(equalTo: view.widthAnchor)
        ]

        mainBottomConstraint = mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        mainConstraints.append(mainBottomConstraint)

        NSLayoutConstraint.activate(mainConstraints)

        isMenuOpen = false
        updateMainDimming(forMenuLeading: sideMenuLeadingConstraint.constant)
    }

    private func configureGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
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
        let settingsView = SettingsView().environmentObject(settingsManager)
        let settingsVC = UIHostingController(rootView: settingsView)
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

    private func updateMainDimming(forMenuLeading leading: CGFloat) {
        let progress = max(0, min(1, 1 + (leading / sideMenuWidth)))
        let alpha = progress * maxMainDimmingAlpha
        mainDimmingView.alpha = alpha
        mainDimmingView.isUserInteractionEnabled = alpha > 0.001
    }

    private func dismissKeyboardIfNeeded() {
        view.endEditing(true)
    }

    func toggleMenu(open: Bool, animated: Bool) {
        let wasMenuOpen = isMenuOpen
        if open || wasMenuOpen {
            dismissKeyboardIfNeeded()
        }

        isMenuOpen = open
        let finalLeading = open ? 0 : -sideMenuWidth

        if animated {
            UIView.animate(withDuration: menuAnimationDuration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: {
                self.sideMenuLeadingConstraint.constant = finalLeading
                self.updateMainDimming(forMenuLeading: finalLeading)
                self.view.layoutIfNeeded()
            })
        } else {
            sideMenuLeadingConstraint.constant = finalLeading
            updateMainDimming(forMenuLeading: finalLeading)
            view.layoutIfNeeded()
        }
    }

    @objc
    private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view).x

        switch gesture.state {
        case .began:
            startMenuLeading = sideMenuLeadingConstraint.constant
        case .changed:
            let newLeading = startMenuLeading + translation
            sideMenuLeadingConstraint.constant = max(-sideMenuWidth, min(0, newLeading))
            updateMainDimming(forMenuLeading: sideMenuLeadingConstraint.constant)
        case .ended, .cancelled:
            let velocityX = gesture.velocity(in: view).x
            let currentOffset = sideMenuLeadingConstraint.constant
            let shouldOpen: Bool
            if abs(velocityX) > 300 {
                shouldOpen = velocityX > 0
            } else {
                shouldOpen = (currentOffset > -sideMenuWidth * 0.5)
            }
            toggleMenu(open: shouldOpen, animated: true)
        default:
            break
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension SideMenuContainerViewController: UIGestureRecognizerDelegate {
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
        return vc
    }

    func updateUIViewController(_ uiViewController: SideMenuContainerViewController, context: Context) {
        // No-op
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
