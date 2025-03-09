//
//  SideMenuContainerViewController.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/02/19.
//

#if os(iOS) || os(tvOS)

import SwiftUI
import UIKit

/// 这是给 iOS/iPadOS 使用的 UIViewController，
/// 内含一个左侧 Sidebar(UIHostingController) + 一个主界面(MainContentView) 的 UIHostingController，
/// 并实现手势跟手拖拽展开/收起侧边栏，且主界面不被“压缩”，而是向右偏移。
class SideMenuContainerViewController: UIViewController {

    // 侧边栏宽度
    private let sideMenuWidth: CGFloat = 280

    // 侧边栏控制器、主界面控制器
    private var sidebarHostingController: UIViewController!
    private var mainHostingController: UIViewController!

    // 侧边栏与父视图的leading约束
    private var sideMenuLeadingConstraint: NSLayoutConstraint!

    // 主界面与侧边栏trailing的约束（让它们紧挨着）
    // 注：可单独命名，也可直接写在activate里
    private var mainLeftConstraint: NSLayoutConstraint!

    // 记录当前侧边栏是否展开
    private var isMenuOpen = false

    // 拖拽时的初始 offset
    private var startMenuLeading: CGFloat = 0

    // 用于构建 SwiftUI View 的依赖（从外部传入）
    var chatSessionsViewModel: ChatSessionsViewModel!
    var audioManager: GlobalAudioManager!
    var settingsManager: SettingsManager!

    override func viewDidLoad() {
        super.viewDidLoad()

        // ============= 1) 构建并添加侧边栏 =============
        let sidebarView = SidebarView(
            onConversationTap: { [weak self] session in
                // 切换聊天
                self?.chatSessionsViewModel.selectedSession = session
                // 收起侧边栏
                self?.toggleMenu(open: false, animated: true)
            },
            onOpenSettings: { [weak self] in
                self?.presentSettings()
            }
        )
        .environmentObject(chatSessionsViewModel)

        let sidebarVC = UIHostingController(rootView: sidebarView)
        sidebarHostingController = sidebarVC

        addChild(sidebarVC)
        view.addSubview(sidebarVC.view)
        sidebarVC.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarVC.didMove(toParent: self)

        // ============= 2) 构建并添加主界面 =============
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
        mainHostingController = mainVC

        addChild(mainVC)
        view.addSubview(mainVC.view)
        mainVC.view.translatesAutoresizingMaskIntoConstraints = false
        mainVC.didMove(toParent: self)

        // ============= 3) 设置AutoLayout约束 =============

        // -- 侧边栏布局 --
        // 初始时leading = -sideMenuWidth，表示完全在屏幕左侧之外
        sideMenuLeadingConstraint = sidebarVC.view.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: -sideMenuWidth
        )

        NSLayoutConstraint.activate([
            sideMenuLeadingConstraint,
            sidebarVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarVC.view.widthAnchor.constraint(equalToConstant: sideMenuWidth)
        ])

        // -- 主界面布局 --
        // 主界面的leading贴在sidebar的trailing，这样二者紧挨
        // 宽度则与父视图等宽，保证不被“压缩”
        mainLeftConstraint = mainVC.view.leadingAnchor.constraint(
            equalTo: sidebarVC.view.trailingAnchor, constant: 0
        )

        NSLayoutConstraint.activate([
            mainLeftConstraint,
            mainVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            mainVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainVC.view.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])

        // 默认侧边栏“关闭”（leading = -sideMenuWidth）
        isMenuOpen = false

        // ============= 4) 添加Pan手势以实现“跟手拖拽” =============
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    private func presentSettings() {
        // 弹出 SwiftUI 的 SettingsView
        let settingsView = SettingsView().environmentObject(settingsManager)
        let settingsVC = UIHostingController(rootView: settingsView)
        settingsVC.modalPresentationStyle = .formSheet
        present(settingsVC, animated: true, completion: nil)
    }

    /// 切换侧边栏展开/收起
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

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view).x

        switch gesture.state {
        case .began:
            startMenuLeading = sideMenuLeadingConstraint.constant
        case .changed:
            // sideMenuLeadingConstraint 在 [-sideMenuWidth, 0]之间移动
            let newLeading = startMenuLeading + translation
            sideMenuLeadingConstraint.constant = max(-sideMenuWidth, min(0, newLeading))
        case .ended, .cancelled:
            let velocityX = gesture.velocity(in: view).x
            let currentOffset = sideMenuLeadingConstraint.constant

            // 根据惯性+当前位置判断是展开还是收起
            let shouldOpen: Bool
            if abs(velocityX) > 300 {
                // 如果速度大于某阈值，则根据速度方向判断
                shouldOpen = velocityX > 0
            } else {
                // 否则根据当前位置是否超过一半来判断
                shouldOpen = (currentOffset > -sideMenuWidth * 0.5)
            }

            toggleMenu(open: shouldOpen, animated: true)
        default:
            break
        }
    }
}

// 让其他手势（子视图的 ScrollView 等）能/不能与 panGesture 共存
extension SideMenuContainerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

/// SwiftUI 包装：在 iOS 下使用此 Representable 来展示自定义容器控制器
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
        // 不需要实时更新
    }
}

#endif
