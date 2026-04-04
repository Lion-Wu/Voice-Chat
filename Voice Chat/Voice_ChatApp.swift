//
//  Voice_ChatApp.swift
//  Voice Chat
//
//  Created by Lion Wu on 2023/12/25.
//

import SwiftUI
import SwiftData

enum AppLocalization {
    static var supportedLocalizationIdentifiers: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }
    }

    static func localizedPlaceholderTitles() -> Set<String> {
        var identifiers = Set(supportedLocalizationIdentifiers)
        identifiers.insert("en")
        identifiers.insert(Locale.current.identifier)

        return Set(
            identifiers.map { identifier in
                String(localized: "New Chat", locale: Locale(identifier: identifier))
            }
        )
    }

}

@main
@MainActor
struct Voice_ChatApp: App {
    @StateObject private var appEnvironment = AppEnvironment()
    @StateObject private var startupCoordinator = StartupDataCoordinator()

    var body: some Scene {
        WindowGroup {
            StartupDataGateView(coordinator: startupCoordinator) { container in
                ContentView()
                    .environmentObject(appEnvironment)
                    .environmentObject(appEnvironment.audioManager)
                    .environmentObject(appEnvironment.settingsManager)
                    .environmentObject(appEnvironment.chatSessionsViewModel)
                    .environmentObject(appEnvironment.speechInputManager)
                    .environmentObject(appEnvironment.errorCenter)
                    .environmentObject(appEnvironment.voiceOverlayViewModel)
                    // Bind the SwiftData context once for all shared dependencies.
                    .background(
                        ModelContextBinder()
                            .environmentObject(appEnvironment)
                    )
                    .modelContainer(container)
            }
        }

        #if os(macOS)
        Settings {
            StartupDataGateView(coordinator: startupCoordinator) { container in
                SettingsView(settingsManager: appEnvironment.settingsManager)
                    .environmentObject(appEnvironment)
                    .environmentObject(appEnvironment.errorCenter)
                    .background(
                        ModelContextBinder()
                            .environmentObject(appEnvironment)
                    )
                    .modelContainer(container)
            }
        }
        .commands {
            AppMenuCommands(appEnvironment.chatSessionsViewModel)
        }
        #endif
    }
}

#if os(macOS)
/// Custom app-level menu that replaces the default `.newItem` command with "New Chat".
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
