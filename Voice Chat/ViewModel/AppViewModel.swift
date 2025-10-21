//
//  AppViewModel.swift
//  Voice Chat
//
//  Created by OpenAI Assistant on 2024/05/08.
//

import Foundation
#if os(macOS)
import AppKit
#endif

/// Coordinates top-level application behaviors that do not belong to a specific screen.
@MainActor
final class AppViewModel: ObservableObject {
    #if os(macOS)
    /// Presents the dedicated settings window on macOS so that the UI remains consistent with native apps.
    func presentSettings() {
        NSApp.sendAction(#selector(NSApplication.showSettingsWindow(_:)), to: nil, from: nil)
    }
    #else
    /// Tracks whether the settings sheet is visible on platforms that do not use a dedicated settings window.
    @Published var isPresentingSettings: Bool = false

    func presentSettings() {
        isPresentingSettings = true
    }

    func dismissSettings() {
        isPresentingSettings = false
    }
    #endif
}
