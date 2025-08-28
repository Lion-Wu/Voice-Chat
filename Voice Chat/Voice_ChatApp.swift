//
//  Voice_ChatApp.swift
//  Voice Chat
//
//  Created by Lion Wu on 2023/12/25.
//

import SwiftUI

@main
@MainActor
struct Voice_ChatApp: App {
    @StateObject private var audioManager = GlobalAudioManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var chatSessionsViewModel = ChatSessionsViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
                .environmentObject(settingsManager)
                .environmentObject(chatSessionsViewModel)
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(settingsManager)
        }
        .commands {
            AppMenuCommands(chatSessionsViewModel)
        }
        #endif
    }
}

#if os(macOS)
/// 自定义应用级菜单命令：将系统的 .newItem（默认新建窗口/文档）替换为 “New Chat”
private struct AppMenuCommands: Commands {
    @ObservedObject var chatSessionsViewModel: ChatSessionsViewModel

    init(_ vm: ChatSessionsViewModel) {
        self._chatSessionsViewModel = ObservedObject(wrappedValue: vm)
    }

    var body: some Commands {
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
