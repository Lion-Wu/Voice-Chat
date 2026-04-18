//
//  Voice_ChatApp.swift
//  Voice Chat
//
//  Created by Lion Wu on 2023/12/25.
//

import SwiftUI
import SwiftData

@main
@MainActor
struct Voice_ChatApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
        #if os(visionOS)
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentMinSize)
        #endif
        .onChange(of: scenePhase) { _, newPhase in
            appEnvironment.updatePersistenceMode(for: newPhase)
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
