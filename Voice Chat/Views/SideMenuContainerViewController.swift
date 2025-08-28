//
//  SideMenuContainerViewController.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/02/19.
//

#if os(iOS) || os(tvOS)

import SwiftUI
import UIKit

/// iOS/iPadOS 使用的容器控制器：左侧 Sidebar + 右侧主视图（MainContentView）。
/// 采用跟手拖拽展开/收起侧边栏，主视图不缩放，仅水平位移。
final class SideMenuContainerViewController: UIViewController {

    // MARK: - Layout Constants
    private let sideMenuWidth: CGFloat = 325

    // MARK: - Child Controllers
    private var sidebarHostingController: UIViewController!
    private var mainHostingController: UIViewController!

    // MARK: - Constraints
    private var sideMenuLeadingConstraint: NSLayoutConstraint!
    private var mainLeftConstraint: NSLayoutConstraint!

    // MARK: - State
    private var isMenuOpen = false
    private var startMenuLeading: CGFloat = 0

    // MARK: - Dependencies
    var chatSessionsViewModel: ChatSessionsViewModel!
    var audioManager: GlobalAudioManager!
    var settingsManager: SettingsManager!

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureConstraints()
        configureGestures()
    }

    // MARK: - Setup
    private func configureHierarchy() {
        // Sidebar
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

        // Main
        let mainView = MainContentView(
            onToggleSidebar: { [weak self] in
                guard let self = self else { return }
                self.toggleMenu(open: !self.isMenuOpen, animated: true)
            }
        )
        .environmentObject(chatSessionsViewModel)
        .environmentObject(audioManager)
        .environmentObject(settingsManager)

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

        // Sidebar constraints
        sideMenuLeadingConstraint = sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -sideMenuWidth)
        NSLayoutConstraint.activate([
            sideMenuLeadingConstraint,
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: sideMenuWidth)
        ])

        // Main constraints
        mainLeftConstraint = mainView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: 0)
        NSLayoutConstraint.activate([
            mainLeftConstraint,
            mainView.topAnchor.constraint(equalTo: view.topAnchor),
            mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainView.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])

        isMenuOpen = false
    }

    private func configureGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    // MARK: - Actions
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

// MARK: - Gesture Delegate
extension SideMenuContainerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

// MARK: - SwiftUI Bridge
struct SideMenuContainerRepresentable: UIViewControllerRepresentable {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var settingsManager: SettingsManager

    func makeUIViewController(context: Context) -> SideMenuContainerViewController {
        let vc = SideMenuContainerViewController()
        vc.chatSessionsViewModel = chatSessionsViewModel
        vc.audioManager = audioManager
        vc.settingsManager = settingsManager
        return vc
    }

    func updateUIViewController(_ uiViewController: SideMenuContainerViewController, context: Context) {
        // No-op
    }
}

#endif
