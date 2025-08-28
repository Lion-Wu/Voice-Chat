//
//  Voice_ChatApp.swift
//  Voice Chat
//
//  Created by Lion Wu on 2023/12/25.
//

import SwiftUI

@main
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
        // 系统级设置窗口（⌘,）保持不变
        Settings {
            SettingsView()
                .environmentObject(settingsManager)
        }
        // 替换系统的 “New” 命令（默认新建窗口）为 “New Chat”
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

    /// 通过构造函数把 ViewModel 传入，避免 .environmentObject（Commands 不支持）
    init(_ vm: ChatSessionsViewModel) {
        self._chatSessionsViewModel = ObservedObject(wrappedValue: vm)
    }

    var body: some Commands {
        // 用我们自己的按钮替换系统的“新建”命令组（含 ⌘N）
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                // 双重保险：即使 UI 层禁用出问题，这里也不执行
                guard chatSessionsViewModel.canStartNewSession else { return }
                chatSessionsViewModel.startNewSession()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!chatSessionsViewModel.canStartNewSession)
        }

        // 其他默认命令（如 Preferences/Settings ⌘,）保持系统行为
    }
}
#endif
