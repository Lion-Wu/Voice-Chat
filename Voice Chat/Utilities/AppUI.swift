//
//  AppUI.swift
//  Voice Chat
//
//  Created by OpenAI Assistant on 2024/05/25.
//

import Foundation

#if os(macOS)
import AppKit
#endif

enum AppUI {
#if os(macOS)
    static func openSettingsWindow() {
        NSApp.sendAction(#selector(NSApplication.showSettingsWindow(_:)), to: nil, from: nil)
    }
#else
    static func openSettingsWindow() { }
#endif
}
