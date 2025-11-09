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

    private var sidebarHostingController: UIViewController!
    private var mainHostingController: UIViewController!

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

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureConstraints()
        configureGestures()
    }

    private func configureHierarchy() {
        let sidebarView = SidebarView(
            onConversationTap: { [weak self] session in
                self?.chatSessionsViewModel.selectedSession = session
                self?.toggleMenu(open: false, animated: true)
            },
            onOpenSettings: { [weak self] in
                self?.presentSettings()
            }
        )
        .environmentObject(chatSessionsViewModel)

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

        let mainVC = UIHostingController(rootView: mainView)
        self.mainHostingController = mainVC

        addChild(mainVC)
        view.addSubview(mainVC.view)
        mainVC.view.translatesAutoresizingMaskIntoConstraints = false
        mainVC.didMove(toParent: self)
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

        if #available(iOS 15.0, tvOS 15.0, *) {
            let keyboardGuide = view.keyboardLayoutGuide
            mainBottomConstraint = mainView.bottomAnchor.constraint(equalTo: keyboardGuide.topAnchor)
        } else {
            mainBottomConstraint = mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        }
        mainConstraints.append(mainBottomConstraint)

        NSLayoutConstraint.activate(mainConstraints)

        isMenuOpen = false
    }

    private func configureGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    private func presentSettings() {
        let settingsView = SettingsView().environmentObject(settingsManager)
        let settingsVC = UIHostingController(rootView: settingsView)
        settingsVC.modalPresentationStyle = .formSheet
        present(settingsVC, animated: true, completion: nil)
    }

    func toggleMenu(open: Bool, animated: Bool) {
        isMenuOpen = open
        let finalLeading = open ? 0 : -sideMenuWidth
        if animated {
            UIView.animate(withDuration: 0.3, animations: {
                self.sideMenuLeadingConstraint.constant = finalLeading
                self.view.layoutIfNeeded()
            })
        } else {
            sideMenuLeadingConstraint.constant = finalLeading
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
    // Propagate the shared speech input manager into the UIKit container.
    @EnvironmentObject var speechInputManager: SpeechInputManager

    func makeUIViewController(context: Context) -> SideMenuContainerViewController {
        let vc = SideMenuContainerViewController()
        vc.chatSessionsViewModel = chatSessionsViewModel
        vc.audioManager = audioManager
        vc.settingsManager = settingsManager
        vc.speechInputManager = speechInputManager
        return vc
    }

    func updateUIViewController(_ uiViewController: SideMenuContainerViewController, context: Context) {
        // No-op
    }
}

#endif
