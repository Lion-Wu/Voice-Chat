//
//  AppMenuCommands.swift
//  Voice Chat
//
//  Created by Lion Wu on 2023/12/25.
//

#if os(macOS)
import SwiftUI

/// App-level commands for the About window and starting a new chat.
struct AppMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var chatSessionsViewModel: ChatSessionsViewModel

    init(_ vm: ChatSessionsViewModel) {
        self._chatSessionsViewModel = ObservedObject(wrappedValue: vm)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(ApplicationInformation.name)") {
                openWindow(id: AboutView.windowID)
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                guard chatSessionsViewModel.canStartNewSession else { return }
                chatSessionsViewModel.startNewSession()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!chatSessionsViewModel.canStartNewSession)
        }
    }
}
#endif
