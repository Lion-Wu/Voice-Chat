//
//  RealtimeVoiceWindowController.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/27.
//

#if os(macOS)

import SwiftUI
import Combine
import AppKit

@MainActor
final class RealtimeVoiceWindowController: NSObject, NSWindowDelegate {
    private weak var mainWindow: NSWindow?
    private var overlayWindow: NSWindow?
    private var presentationCancellable: AnyCancellable?
    private var mainWindowObserver: NSObjectProtocol?
    private var mainWindowExitFullScreenObserver: NSObjectProtocol?
    private var isPresentingOverlay = false
    private var pendingOverlayPresentation = false
    private var shouldRestoreMainWindowFullScreen = false
    private var isWaitingForMainWindowExitFullScreen = false
    private let overlayViewModel: VoiceChatOverlayViewModel
    private let errorCenter: AppErrorCenter

    init(
        overlayViewModel: VoiceChatOverlayViewModel,
        errorCenter: AppErrorCenter
    ) {
        self.overlayViewModel = overlayViewModel
        self.errorCenter = errorCenter
        super.init()
        bindPresentationChanges()
    }

    @MainActor deinit {
        if let observer = mainWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = mainWindowExitFullScreenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func registerMainWindow(_ window: NSWindow?) {
        guard let window else { return }
        mainWindow = window
        if let observer = mainWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        mainWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPresentingOverlay else { return }
                self.hideMainWindowSafely()
            }
        }
    }

    private func bindPresentationChanges() {
        presentationCancellable = overlayViewModel.$isPresented
            .removeDuplicates()
            .sink { [weak self] presented in
                guard let self else { return }
                if presented {
                    self.isPresentingOverlay = true
                    showOverlayWindow()
                } else {
                    self.isPresentingOverlay = false
                    pendingOverlayPresentation = false
                    closeOverlayWindow()
                    restoreMainWindowIfNeeded()
                }
            }
    }

    private func showOverlayWindow() {
        shouldRestoreMainWindowFullScreen = false
        pendingOverlayPresentation = false
        hideMainWindowSafely()
    }

    private func presentOverlayWindow() {
        guard isPresentingOverlay else { return }

        if let window = overlayWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = RealtimeVoiceOverlayView(viewModel: overlayViewModel)
            .environmentObject(errorCenter)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = NSLocalizedString("Realtime Voice", comment: "Window title for realtime voice mode")
        window.isReleasedWhenClosed = false
        window.styleMask.insert(.fullSizeContentView)
        window.delegate = self
        window.setFrameAutosaveName("RealtimeVoiceOverlayWindow")

        overlayWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeOverlayWindow() {
        guard let window = overlayWindow else { return }
        overlayWindow = nil
        window.close()
    }

    private func hideMainWindowSafely() {
        let shouldHide = isPresentingOverlay || pendingOverlayPresentation
        guard shouldHide else { return }
        guard let window = resolveMainWindow() else {
            presentOverlayWindow()
            return
        }

        mainWindow = window

        if window.styleMask.contains(.fullScreen) {
            if !shouldRestoreMainWindowFullScreen {
                shouldRestoreMainWindowFullScreen = true
            }
            pendingOverlayPresentation = true
            guard !isWaitingForMainWindowExitFullScreen else { return }
            isWaitingForMainWindowExitFullScreen = true
            if let observer = mainWindowExitFullScreenObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            mainWindowExitFullScreenObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isWaitingForMainWindowExitFullScreen = false
                    if let observer = self.mainWindowExitFullScreenObserver {
                        NotificationCenter.default.removeObserver(observer)
                        self.mainWindowExitFullScreenObserver = nil
                    }
                    self.handleMainWindowExitedFullScreen()
                }
            }
            // Exit full screen before hiding to avoid leaving an empty Space.
            window.toggleFullScreen(nil)
            return
        }

        window.orderOut(nil)
        presentOverlayWindow()
    }

    private func handleMainWindowExitedFullScreen() {
        let shouldHide = isPresentingOverlay || pendingOverlayPresentation
        guard let window = mainWindow else {
            if isPresentingOverlay {
                presentOverlayWindow()
            }
            pendingOverlayPresentation = false
            return
        }
        guard shouldHide else {
            restoreMainWindowFullScreenIfNeeded(window)
            return
        }
        pendingOverlayPresentation = false
        window.orderOut(nil)
        presentOverlayWindow()
    }

    private func resolveMainWindow() -> NSWindow? {
        if let window = mainWindow {
            return window
        }
        if let window = NSApp.mainWindow, !isOverlayWindow(window) {
            return window
        }
        return NSApp.windows.first(where: { $0.isVisible && !isOverlayWindow($0) })
    }

    private func isOverlayWindow(_ window: NSWindow) -> Bool {
        guard let overlayWindow else { return false }
        return window === overlayWindow
    }

    private func restoreMainWindowIfNeeded() {
        guard let window = mainWindow else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard !isWaitingForMainWindowExitFullScreen else { return }
        restoreMainWindowFullScreenIfNeeded(window)
    }

    private func restoreMainWindowFullScreenIfNeeded(_ window: NSWindow) {
        guard shouldRestoreMainWindowFullScreen else { return }
        shouldRestoreMainWindowFullScreen = false
        guard !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if overlayViewModel.isPresented {
            overlayViewModel.dismiss()
        }
        overlayWindow = nil
    }
}

#endif
