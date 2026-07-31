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
    @StateObject private var appEnvironment: AppEnvironment
    @StateObject private var startupCoordinator: StartupDataCoordinator

    init() {
        let appEnvironment = AppEnvironment()
        let startupCoordinator = StartupDataCoordinator { [weak appEnvironment] container in
            appEnvironment?.start(with: container)
        }
        appEnvironment.settingsManager.onPersistentStoreReadFailure = { [weak startupCoordinator, weak appEnvironment] error in
            appEnvironment?.quiescePersistentStore()
            startupCoordinator?.reportPersistentStoreReadFailure(error)
        }
        appEnvironment.chatSessionsViewModel.onPersistentStoreReadFailure = { [weak startupCoordinator, weak appEnvironment] error in
            appEnvironment?.quiescePersistentStore()
            startupCoordinator?.reportPersistentStoreReadFailure(error)
        }
        startupCoordinator.onWillResetPersistentStore = { [weak appEnvironment] in
            appEnvironment?.quiescePersistentStore()
        }
        _appEnvironment = StateObject(wrappedValue: appEnvironment)
        _startupCoordinator = StateObject(wrappedValue: startupCoordinator)
    }

    var body: some Scene {
        WindowGroup {
            StartupDataGateView(
                coordinator: startupCoordinator,
                loadingContent: {
                    mainContent(isPersistentDataReady: false)
                },
                readyContent: { container in
                    mainContent(isPersistentDataReady: true)
                        .modelContainer(container)
                }
            )
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
            StartupDataGateView(
                coordinator: startupCoordinator,
                loadingContent: {
                    StartupSettingsLoadingView()
                },
                readyContent: { container in
                    SettingsView(settingsManager: appEnvironment.settingsManager)
                        .environmentObject(appEnvironment)
                        .environmentObject(appEnvironment.errorCenter)
                        .modelContainer(container)
                }
            )
        }
        .commands {
            AppMenuCommands(appEnvironment.chatSessionsViewModel)
        }
        #endif
    }

    private func mainContent(isPersistentDataReady: Bool) -> some View {
        ContentView(isPersistentDataReady: isPersistentDataReady)
            .environmentObject(appEnvironment)
            .environmentObject(appEnvironment.audioManager)
            .environmentObject(appEnvironment.settingsManager)
            .environmentObject(appEnvironment.chatSessionsViewModel)
            .environmentObject(appEnvironment.speechInputManager)
            .environmentObject(appEnvironment.errorCenter)
            .environmentObject(appEnvironment.voiceOverlayViewModel)
    }
}
