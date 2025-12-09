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
                guard let self, self.overlayViewModel.isPresented else { return }
                self.hideMainWindow()
            }
        }
    }

    private func bindPresentationChanges() {
        presentationCancellable = overlayViewModel.$isPresented
            .removeDuplicates()
            .sink { [weak self] presented in
                guard let self else { return }
                if presented {
                    showOverlayWindow()
                } else {
                    closeOverlayWindow()
                    restoreMainWindowIfNeeded()
                }
            }
    }

    private func showOverlayWindow() {
        hideMainWindow()

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

    private func hideMainWindow() {
        if let window = mainWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            mainWindow = window
            window.orderOut(nil)
        }
    }

    private func restoreMainWindowIfNeeded() {
        guard let window = mainWindow else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
